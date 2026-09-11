#!/usr/bin/env bash
# Spawn the firewalling and intrusion detection lab: a server and a workstation
# on an inside segment, an attacker and a customer on an outside segment, and
# one router between them. Self-contained -- drives docker + the veth primitives
# directly, WITHOUT the full platform/startup.sh pipeline (RQ1).
#
#   client --\                          /-- attacker  (124.1.0.66, 124.9.0.66)
#             [ S1 ] --- router --- [ S2 ]
#   server --/                          \-- customer  (124.1.0.77)
#
# Each segment has a switch of its own, and no port of one is a port of the
# other. The only path from the outside to the server is therefore through the
# router, and the server sees every outside packet arrive on one interface with
# its original source address on it.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$SERVER_CTN"; then
    echo "Lab already spawned ($SERVER_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# Part 3 puts Suricata inline by sending packets to a netfilter queue, which
# needs two kernel modules the container cannot autoload for itself: xt_NFQUEUE
# for the iptables target, and nfnetlink_queue for the socket Suricata binds.
# Autoloading either needs privilege in the initial namespace, which a rootless
# daemon's containers do not have. On a host where nothing has loaded them, the
# learner's first NFQUEUE rule would fail halfway through Part 3 with an error
# they have no way to interpret. Fail here instead, with the reason.
log "checking this host can queue packets to a userspace program from inside a container"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        "iptables -I INPUT -p tcp --dport 65000 -j NFQUEUE --queue-num 99 \
         && iptables -D INPUT -p tcp --dport 65000 -j NFQUEUE --queue-num 99" \
        >/dev/null 2>&1; then
    echo "this host cannot install an iptables NFQUEUE rule inside a container." >&2
    echo "Part 3 needs one: it is how Suricata is put inline. The xt_NFQUEUE and" >&2
    echo "nfnetlink_queue modules must be loaded on the host; load them with" >&2
    echo "  sudo modprobe xt_NFQUEUE nfnetlink_queue" >&2
    echo "on a machine where you have root, and spawn again. Parts 1 and 2 work" >&2
    echo "without them." >&2
    exit 1
fi

# Every container is given an explicit command, which is what stops the base
# image's default CMD (`sshd -D -e`) from running. The server runs sshd because
# default_config/server.sh starts it, on purpose and as one of the three
# listeners the lab discusses; nothing else in the lab should have a listener on
# 22 that nobody put there.
IDLE_CMD=(sleep infinity)

# --init everywhere. PID 1 would otherwise be `sleep infinity`, which never calls
# wait(). The server forks a login shell for every telnet session and the two
# clients fork a curl or an nping per step, and without docker-init they
# accumulate as zombies for as long as the lab is up.

# ip_forward is set at creation rather than by default_config/router.sh, because
# Docker mounts /proc/sys read-only in an unprivileged container. It is set on
# the router and explicitly to 0 everywhere else, because "only the router
# forwards" is a fact the lab is built on and a reader of this file should not
# have to know what the default is to find it.
log "starting router $RTR_CTN (two segments, forwarding on, no translation)"
docker run -d --name "$RTR_CTN" --network=none --init \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=1 \
    --hostname router \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

for role in server client attacker customer; do
    ctn="$( ctn_of "$role" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 \
        --hostname "$role" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# The two switches. --cap-add=ALL minus SYS_RESOURCE is what the mini-internet's
# own switch containers run with; ovs-vswitchd needs most of it, and SYS_RESOURCE
# is dropped because raising RLIMIT_MEMLOCK is exactly what fails in a user
# namespace.
for sw in "${SWITCHES[@]}"; do
    ctn="$( ctn_of "$sw" )"
    log "starting switch $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$sw" \
        "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null
done

# No STP and no VLANs: each segment is one flat broadcast domain, and the switch
# is not what this lab is about.
for sw in "${SWITCHES[@]}"; do
    ctn="$( ctn_of "$sw" )"
    log "waiting for Open vSwitch in $ctn"
    for _ in $(seq 1 60); do
        if docker exec "$ctn" ovs-vsctl show >/dev/null 2>&1; then break; fi
        sleep 0.5
    done
    docker exec "$ctn" ovs-vsctl show >/dev/null 2>&1 || {
        echo "Open vSwitch did not come up in $ctn" >&2; exit 1; }
    log "creating bridge $BR in $ctn"
    docker exec "$ctn" ovs-vsctl --may-exist add-br "$BR" >/dev/null
    docker exec "$ctn" ovs-vsctl set bridge "$BR" stp_enable=false >/dev/null
done

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

# Wire a device into one of the two switches. The switch end is brought up and
# added to that switch's bridge.
wire_to_switch() {   # <container> <interface inside it> <switch port name> <switch container>
    i=$(( i + 1 ))
    local ta="vi${i}a" tb="vi${i}b" pid
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    pid="$( docker inspect -f '{{.State.Pid}}' "$4" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$3"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$3" up
    docker exec "$4" ovs-vsctl add-port "$BR" "$3" >/dev/null
}

log "wiring inside: $RTR_CTN($RTR_INSIDE_IF) -> $SW_IN_CTN port $( sw_port_of rtrlan )"
wire_to_switch "$RTR_CTN" "$RTR_INSIDE_IF" "$( sw_port_of rtrlan )" "$SW_IN_CTN"
for role in server client; do
    log "wiring inside: $( ctn_of "$role" )($LAN_IF) -> $SW_IN_CTN port $( sw_port_of "$role" )"
    wire_to_switch "$( ctn_of "$role" )" "$LAN_IF" "$( sw_port_of "$role" )" "$SW_IN_CTN"
done

log "wiring outside: $RTR_CTN($RTR_OUTSIDE_IF) -> $SW_OUT_CTN port $( sw_port_of rtrext )"
wire_to_switch "$RTR_CTN" "$RTR_OUTSIDE_IF" "$( sw_port_of rtrext )" "$SW_OUT_CTN"
for role in attacker customer; do
    log "wiring outside: $( ctn_of "$role" )($EXT_IF) -> $SW_OUT_CTN port $( sw_port_of "$role" )"
    wire_to_switch "$( ctn_of "$role" )" "$EXT_IF" "$( sw_port_of "$role" )" "$SW_OUT_CTN"
done

# Apply the per-device starter configs in the order lib.sh defines: the router
# first so there is a path between the segments, then the server whose services
# the rest of the lab aims at, then the three machines that use them.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. The server has three listeners, no filter rules and no Suricata."
log "Check it with:  $LAB_DIR/scripts/status.sh"
