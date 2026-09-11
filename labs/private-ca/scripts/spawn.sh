#!/usr/bin/env bash
# Spawn the private-CA web service lab: one OVS switch, a certificate authority,
# the web server the certificate is issued for, and the client that decides
# whether to believe it. Self-contained — drives docker + the veth/OVS primitives
# directly, WITHOUT the full platform/startup.sh pipeline (proposal RQ1).
#
#   ca ---\
#          >--- S1 (OVS bridge) ---- server
#   client/
#
# One flat /24, no router, nothing filtering. Everything this lab measures
# happens above the transport, so the network underneath is deliberately as
# uninteresting as it can be made.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

# Open vSwitch is NOT required on the host: every ovs-vsctl call in this lab runs
# inside the switch container, whose image ships OVS. Docker reachability is the
# real prerequisite, and it covers an unreachable daemon as well as a stopped one.
command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and can this account reach it? (try: docker info)" >&2
    exit 1
}

# Captured before it is tested. `docker ps -a | grep -qx` looks equivalent and is
# not: grep -q exits at the first match, docker ps takes SIGPIPE, and under this
# script's `set -o pipefail` the pipeline reports failure on exactly the runs
# where the container WAS found, so the guard would wave through a second spawn.
existing="$( docker ps -a --format '{{.Names}}' )"
case $'\n'"$existing"$'\n' in
    *$'\n'"$SW_CTN"$'\n'*)
        echo "Lab already spawned ($SW_CTN exists). Run teardown.sh first." >&2
        exit 1 ;;
esac

ensure_images

# 1. Containers. No data-plane network: the OVS bridge is the only fabric.
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

# Every container is given an explicit command, which is what stops the base
# image's default CMD (`sshd -D -e`) from running. Only the CA is meant to accept
# an SSH session, and its own starter config is what starts the daemon there.
#
# --init on all three. Their PID 1 would otherwise be `sleep infinity`, which
# never calls wait(), so every sshd, lighttpd and openssl child that exits stays
# in the process table as a zombie. On the server that is not merely untidy: the
# handout has the learner stop lighttpd with `pkill -x lighttpd` between
# certificate changes, and a table full of dead lighttpds makes what `ps` shows
# disagree with what is listening.
IDLE_CMD=(sleep infinity)

for h in "${HOSTS[@]}"; do
    ctn="$( ctn_of "$h" )"
    log "starting host $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --hostname "$h" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# 2. The bridge. STP is left off: one switch, no loops, and STP would hold every
#    port in listening/learning for 15 to 30 seconds before the first packet.
log "waiting for Open vSwitch in $SW_CTN"
for _ in $(seq 1 40); do
    if docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1; then break; fi
    sleep 0.5
done
log "creating bridge br0"
docker exec "$SW_CTN" ovs-vsctl \
    -- add-br br0 \
    -- set bridge br0 stp_enable=false \
    -- set-fail-mode br0 standalone >/dev/null

# 3. Wire each host to the switch with a veth pair (inlined, self-contained
#    equivalent of the platform's connect_one_l2_host).
# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else. helper_stop
# is trapped so the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0
wire_host_to_switch() {
    local host_ctn="$1" host_if="$2" sw_port="$3"
    i=$(( i + 1 ))
    local ta="vh${i}a" tb="vh${i}b" hpid spid
    hpid="$( docker inspect -f '{{.State.Pid}}' "$host_ctn" )"
    spid="$( docker inspect -f '{{.State.Pid}}' "$SW_CTN" )"
    helper ip link add "$ta" type veth peer name "$tb"
    helper ip link set "$ta" netns "$hpid"
    helper ip link set "$tb" netns "$spid"
    helper nsenter --net="/proc/$hpid/ns/net" ip link set dev "$ta" name "$host_if"
    helper nsenter --net="/proc/$hpid/ns/net" ip link set dev "$host_if" up
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$tb" name "$sw_port"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$sw_port" up
    docker exec "$SW_CTN" ovs-vsctl add-port br0 "$sw_port" >/dev/null
}

for h in "${HOSTS[@]}"; do
    log "wiring $h -> $SW_CTN (host if $HOST_IF, switch port ${AS}-${h})"
    wire_host_to_switch "$( ctn_of "$h" )" "$HOST_IF" "${AS}-${h}"
done

# 4. Apply the per-device starter configs, the CA first so its SSH daemon and its
#    key pair exist before the other two are given a copy of the key.
for h in "${HOSTS[@]}"; do
    ctn="$( ctn_of "$h" )"
    log "configuring $ctn via default_config/${h}.sh"
    docker cp "$LAB_DIR/default_config/${h}.sh" "$ctn:/home/${h}.sh"
    docker exec "$ctn" chmod 755 "/home/${h}.sh"
    docker exec "$ctn" "/home/${h}.sh"
done

# 5. Distribute the SSH key the CA accepts.
#
#    This is not part of what the lab teaches and it is not something the learner
#    does: a certificate authority reachable by whoever holds a key is the
#    boring, correct arrangement, and the lab needs it only so the two transfers
#    in Part 3 are one command each rather than a digression about SSH. The key
#    is generated inside the CA container by its own starter config and copied
#    out through the host, because no lab container can reach another one's
#    filesystem.
log "distributing the CA's SSH key to the server and the client"
keytmp="$( mktemp -d )"
trap 'helper_stop; rm -rf "$keytmp"' EXIT
docker cp "${CA_CTN}:/root/.ssh/lab_key" "$keytmp/lab_key" >/dev/null
for h in server client; do
    ctn="$( ctn_of "$h" )"
    docker cp "$keytmp/lab_key" "$ctn:/root/.ssh/lab_key" >/dev/null
    docker exec "$ctn" chmod 600 /root/.ssh/lab_key
done

log "lab is up. The server presents a certificate it signed for itself, and the"
log "client trusts nothing that vouches for it."
log "Check it with:  $LAB_DIR/scripts/status.sh"
