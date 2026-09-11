#!/usr/bin/env bash
# Spawn the bastion host and access control lab: an operator's workstation
# outside a site, an edge router that filters nothing, a jump host alone on a DMZ
# segment, and two machines behind the router sharing a switch. Self-contained —
# drives docker + the veth primitives directly, WITHOUT the full
# platform/startup.sh pipeline (proposal RQ1).
#
#   workstation --- edge --- bastion
#                     |
#                  [ br0 ]
#                   |    |
#                  app   db
#
# Two of the three segments are point-to-point and need no switch. The inner
# segment is switched, because app and db have to be able to reach each other
# without their packets crossing the router: no rule the learner writes on the
# edge can affect that path, and Part 5 is about what does.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$EDGE_CTN"; then
    echo "Lab already spawned ($EDGE_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# Part 2's packet filter is an nftables base chain at the forward hook.
# Registering one needs the nf_tables machinery available inside the container's
# namespace, and autoloading a netfilter module needs privilege in the initial
# namespace, which a rootless daemon's containers do not have. On a host where
# nothing has ever loaded it, the learner's first `nft add table` would fail
# halfway through Part 2 with an error they have no way to interpret. Fail here
# instead, with the reason.
log "checking this host can register an nftables forward chain inside a container"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        'nft add table inet nftprobe && nft "add chain inet nftprobe c { type filter hook forward priority filter ; policy accept ; }"' \
        >/dev/null 2>&1; then
    echo "this host cannot register an nftables filter chain inside a container." >&2
    echo "Part 2 needs one. The nf_tables/nft_chain_filter modules must be loaded on" >&2
    echo "the host; any machine already running Docker networking normally has them." >&2
    exit 1
fi

# Every container is given an explicit command, which is what stops the base
# image's default CMD (`sshd -D -e`) from running. Each machine's sshd is started
# by its own starter config instead, with its authentication log redirected to a
# file the oracle reads; the edge router and the workstation run no sshd at all,
# and a stray listener on either would put a service on a port every sweep in
# this lab is read for.
IDLE_CMD=(sleep infinity)

# --init on every machine that runs a daemon. PID 1 would otherwise be `sleep
# infinity`, which never calls wait(), so each sshd child that exits stays in the
# process table as a zombie. That is not merely untidy: `pgrep -x sshd` then
# lists the zombies alongside the listener, and a learner who reloads sshd with a
# pid picked out of pgrep sends SIGHUP to a dead process and sees no error and no
# reload. docker-init reaps them.

# ip_forward is set at creation rather than by default_config/edge.sh: Docker
# mounts /proc/sys read-only in an unprivileged container, and making the router
# privileged just to write one sysctl is more privilege than this lab needs.
# NET_ADMIN is what lets the learner load Part 2's ruleset without the container
# being privileged.
log "starting edge router $EDGE_CTN (forwarding, three segments, no filter)"
docker run -d --name "$EDGE_CTN" --network=none \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=1 \
    --hostname edge \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

for h in bastion app db; do
    ctn="$( ctn_of "$h" )"
    log "starting $ctn (init, sshd)"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --hostname "$h" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

log "starting workstation $WS_CTN"
docker run -d --name "$WS_CTN" --network=none --init \
    --cap-add=NET_ADMIN --hostname workstation \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# The switch. --cap-add=ALL minus SYS_RESOURCE is what the mini-internet's own
# switch containers run with; ovs-vswitchd needs most of it, and SYS_RESOURCE is
# dropped because raising RLIMIT_MEMLOCK is exactly what fails in a user
# namespace.
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

log "waiting for Open vSwitch in $SW_CTN"
for _ in $(seq 1 60); do
    if docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1; then break; fi
    sleep 0.5
done
docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1 || {
    echo "Open vSwitch did not come up in $SW_CTN" >&2; exit 1; }

# No STP and no VLANs: one flat broadcast domain is all the inner segment needs,
# and the switch is not what this lab is about.
log "creating bridge br0 in $SW_CTN"
docker exec "$SW_CTN" ovs-vsctl --may-exist add-br br0 >/dev/null
docker exec "$SW_CTN" ovs-vsctl set bridge br0 stp_enable=false >/dev/null

# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else. helper_stop
# is trapped so the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0

# Put one end of a fresh veth pair into a container and rename it there.
plug() {   # <container> <interface name it should have> <temporary name>
    local ctn="$1" want_if="$2" tmp="$3" pid
    pid="$( docker inspect -f '{{.State.Pid}}' "$ctn" )"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}

wire_point_to_point() {   # <ctnA> <ifA> <ctnB> <ifB>
    i=$(( i + 1 ))
    local ta="vb${i}a" tb="vb${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    plug "$3" "$4" "$tb"
}

# Wire a device into the bridge. The switch end is brought up and added to br0.
wire_to_switch() {   # <container> <interface name inside it> <switch port name>
    i=$(( i + 1 ))
    local ta="vb${i}a" tb="vb${i}b" pid
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    pid="$( docker inspect -f '{{.State.Pid}}' "$SW_CTN" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$3"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$3" up
    docker exec "$SW_CTN" ovs-vsctl add-port br0 "$3" >/dev/null
}

log "wiring external: $WS_CTN($WS_IF) <-> $EDGE_CTN($E_EXT_IF)"
wire_point_to_point "$WS_CTN" "$WS_IF" "$EDGE_CTN" "$E_EXT_IF"
log "wiring dmz:      $BASTION_CTN($BASTION_IF) <-> $EDGE_CTN($E_DMZ_IF)"
wire_point_to_point "$BASTION_CTN" "$BASTION_IF" "$EDGE_CTN" "$E_DMZ_IF"

log "wiring inner:    $EDGE_CTN($E_INNER_IF) -> $SW_CTN port $( sw_port_of edge )"
wire_to_switch "$EDGE_CTN" "$E_INNER_IF" "$( sw_port_of edge )"
log "wiring inner:    $APP_CTN($APP_IF) -> $SW_CTN port $( sw_port_of app )"
wire_to_switch "$APP_CTN" "$APP_IF" "$( sw_port_of app )"
log "wiring inner:    $DB_CTN($DB_IF) -> $SW_CTN port $( sw_port_of db )"
wire_to_switch "$DB_CTN" "$DB_IF" "$( sw_port_of db )"

# Apply the per-device starter configs: the router first so the three segments
# are addressed and forwarding before anything crosses them, then the machines
# behind it, then the workstation outside it.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up, and every machine in the site is reachable from outside it."
log "Check it with:  $LAB_DIR/scripts/status.sh"
