#!/usr/bin/env bash
# Spawn the authoritative DNS lab: a root server holding the three zones above
# uni.lab, three name servers holding nothing at all, and a recursive resolver
# that knows only where the root is. Self-contained — drives docker + the veth
# primitives directly, WITHOUT the full platform/startup.sh pipeline
# (proposal RQ1).
#
#             root   primary   secondary   sub   client
#               |       |          |        |      |
#               +-------+---[ br0 ]+--------+------+
#
# One switched segment, and no router: nothing in this lab crosses a subnet
# boundary. Every machine can reach every other machine from the moment this
# script finishes, so anything that fails afterwards fails in the DNS and
# nowhere else.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$PRIMARY_CTN"; then
    echo "Lab already spawned ($PRIMARY_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# The AAAA record the learner writes in Part 1 names a real address, and the
# lab's last check connects to it, so IPv6 has to work inside a container on this
# host. A kernel booted with ipv6.disable=1 has no inet6 support at all and every
# `ip -6 addr add` fails; failing here names the reason, rather than leaving a
# learner with an AAAA record whose address nothing answers on.
log "checking this host can address IPv6 inside a container"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        'ip -6 addr add fd00:ffff::1/64 dev lo && ip -6 addr del fd00:ffff::1/64 dev lo' \
        >/dev/null 2>&1; then
    echo "this host cannot configure an IPv6 address inside a container." >&2
    echo "Part 1 writes an AAAA record and the lab's last check connects to it." >&2
    echo "A kernel booted with ipv6.disable=1 is the usual cause." >&2
    exit 1
fi

# Every container is given an explicit command, which is what stops the base
# image's default CMD (`sshd -D -e`) from running. No machine in this lab needs
# sshd: everything is reached with docker exec, and a listener on port 22 would
# be a service the lab never mentions.
IDLE_CMD=(sleep infinity)

# --init on every machine. PID 1 would otherwise be `sleep infinity`, which never
# calls wait(), so every short-lived child named or the web server forks stays in
# the process table as a zombie. That is not merely untidy: `pgrep -x named` then
# lists zombies alongside the running daemon, and status.sh reads that pgrep.
for h in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$h" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --hostname "$h" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

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

# No STP and no VLANs: one flat broadcast domain is all this lab needs, and the
# switch is not what it is about.
log "creating bridge br0 in $SW_CTN"
docker exec "$SW_CTN" ovs-vsctl --may-exist add-br br0 >/dev/null
docker exec "$SW_CTN" ovs-vsctl set bridge br0 stp_enable=false >/dev/null

# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else. helper_stop
# is trapped so the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0

# Wire a machine into the bridge. One end of a fresh veth pair goes into the
# container and is renamed there; the other goes into the switch and is added to
# br0.
wire_to_switch() {   # <container> <interface name inside it> <switch port name>
    i=$(( i + 1 ))
    local ta="vb${i}a" tb="vb${i}b" pid
    helper ip link add "$ta" type veth peer name "$tb"
    pid="$( docker inspect -f '{{.State.Pid}}' "$1" )"
    helper ip link set "$ta" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$ta" name "$2"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$2" up
    pid="$( docker inspect -f '{{.State.Pid}}' "$SW_CTN" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$3"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$3" up
    docker exec "$SW_CTN" ovs-vsctl add-port br0 "$3" >/dev/null
}

for h in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$h" )"
    log "wiring $ctn($HOST_IF) -> $SW_CTN port $( sw_port_of "$h" )"
    wire_to_switch "$ctn" "$HOST_IF" "$( sw_port_of "$h" )"
done

# Apply the per-device starter configs in DEVICES order: the root first, so the
# chain above uni.lab answers before anything below it is asked for, then the
# three servers the learner works on, then the client that measures them.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

# named on the root server has to be answering before the first check runs, or a
# learner's opening query fails for a reason that has nothing to do with their
# work.
log "waiting for the root server to answer"
for _ in $(seq 1 40); do
    if docker exec "$CLIENT_CTN" dig +time=1 +tries=1 +norecurse "@$ROOT_IP" . NS >/dev/null 2>&1 \
       && [ "$( dig_status "$( dig_direct "$ROOT_IP" . NS )" )" = "NOERROR" ]; then
        break
    fi
    sleep 0.5
done
[ "$( dig_status "$( dig_direct "$ROOT_IP" . NS )" )" = "NOERROR" ] || {
    echo "the root server did not start answering; check: docker exec $ROOT_CTN cat $NAMED_LOG" >&2
    exit 1; }

log "lab is up. The three servers below the root hold no zone yet, so nothing"
log "under uni.lab resolves."
log "Check it with:  $LAB_DIR/scripts/status.sh"
