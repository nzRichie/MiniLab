#!/usr/bin/env bash
# Spawn the service availability and failover lab: a client on a segment of its
# own, a reverse proxy with a foot in both segments, and two backends sharing a
# switch behind it. Self-contained -- drives docker + the veth primitives
# directly, WITHOUT the full platform/startup.sh pipeline (proposal RQ1).
#
#   client --- proxy --- [ br0 ] --- web1
#                            \------ web2
#
# The front segment is point to point and needs no switch. The back segment is
# switched, because a pool is a set rather than a pair: a third backend is one
# more port on the same bridge and no re-wiring.
#
# The proxy does not forward. net.ipv4.ip_forward is 0 on it, so the client's
# only path to a backend is a TCP connection HAProxy opens on its behalf, and
# every observation about a backend's health has to come from HAProxy's own
# statistics rather than from probing the backend directly.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$PROXY_CTN"; then
    echo "Lab already spawned ($PROXY_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# Part 4's blackhole is an nftables base chain at the input hook, registered
# inside a backend. Registering one needs the nf_tables machinery available in
# the container's namespace, and autoloading a netfilter module needs privilege
# in the initial namespace, which a rootless daemon's containers do not have. On
# a host where nothing has ever loaded it, the learner's first `nft add table`
# would fail halfway through Part 4 with an error they have no way to interpret.
# Fail here instead, with the reason.
log "checking this host can register an nftables input chain inside a container"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        'nft add table inet nftprobe && nft "add chain inet nftprobe c { type filter hook input priority filter ; policy accept ; }"' \
        >/dev/null 2>&1; then
    echo "this host cannot register an nftables filter chain inside a container." >&2
    echo "Part 4 needs one. The nf_tables/nft_chain_filter modules must be loaded on" >&2
    echo "the host; any machine already running Docker networking normally has them." >&2
    exit 1
fi

# Every container is given an explicit command, which is what stops the base
# image's default CMD (`sshd -D -e`) from running. No machine in this lab runs
# sshd, and a stray listener on 22 would put a service on a port that has nothing
# to do with the lab in front of every scan the learner runs.
IDLE_CMD=(sleep infinity)

# --init on the machines that run a daemon. PID 1 would otherwise be `sleep
# infinity`, which never calls wait(), so every short-lived child (each health
# check's connection, each reloaded HAProxy that has finished draining) stays in
# the process table as a zombie. docker-init reaps them.

# ip_forward is set at creation rather than by default_config/proxy.sh: Docker
# mounts /proc/sys read-only in an unprivileged container. It is set explicitly
# to 0 rather than left at the namespace default, because "the proxy does not
# forward" is a fact the lab is built on and a reader of this file should not
# have to know what the default is to find it. NET_ADMIN is what lets the
# starter configs address the interfaces.
log "starting proxy $PROXY_CTN (two segments, forwarding off, haproxy not started)"
docker run -d --name "$PROXY_CTN" --network=none --init \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 \
    --hostname proxy \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

for w in "${BACKENDS[@]}"; do
    ctn="$( ctn_of "$w" )"
    log "starting backend $ctn (init, lighttpd)"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --hostname "$w" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

log "starting client $CLIENT_CTN"
docker run -d --name "$CLIENT_CTN" --network=none --init \
    --cap-add=NET_ADMIN --hostname client \
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

# No STP and no VLANs: one flat broadcast domain is all the back segment needs,
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
    local ta="vf${i}a" tb="vf${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    plug "$3" "$4" "$tb"
}

# Wire a device into the bridge. The switch end is brought up and added to br0.
wire_to_switch() {   # <container> <interface name inside it> <switch port name>
    i=$(( i + 1 ))
    local ta="vf${i}a" tb="vf${i}b" pid
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    pid="$( docker inspect -f '{{.State.Pid}}' "$SW_CTN" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$3"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$3" up
    docker exec "$SW_CTN" ovs-vsctl add-port br0 "$3" >/dev/null
}

log "wiring front: $CLIENT_CTN($CLIENT_IF) <-> $PROXY_CTN($P_FRONT_IF)"
wire_point_to_point "$CLIENT_CTN" "$CLIENT_IF" "$PROXY_CTN" "$P_FRONT_IF"

log "wiring back:  $PROXY_CTN($P_BACK_IF) -> $SW_CTN port $( sw_port_of proxy )"
wire_to_switch "$PROXY_CTN" "$P_BACK_IF" "$( sw_port_of proxy )"
for w in "${BACKENDS[@]}"; do
    log "wiring back:  $( ctn_of "$w" )($WEB_IF) -> $SW_CTN port $( sw_port_of "$w" )"
    wire_to_switch "$( ctn_of "$w" )" "$WEB_IF" "$( sw_port_of "$w" )"
done

# Apply the per-device starter configs: the backends first so there is something
# to balance over before the proxy is addressed, then the proxy, then the client
# that measures both.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. Both backends serve; the proxy in front of them is not running."
log "Check it with:  $LAB_DIR/scripts/status.sh"
