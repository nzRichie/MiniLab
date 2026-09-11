#!/usr/bin/env bash
# Spawn the malware command-and-control traffic analysis lab: three workstations
# on an inside segment, a gateway, and two hosts on an outside segment carrying
# five addresses between them. Self-contained -- drives docker + the veth
# primitives directly, WITHOUT the full platform/startup.sh pipeline (RQ1).
#
#   ws1 --\                          /-- ext1  (118.1.0.10, 118.1.0.30)
#   ws2 --- [ S1 ] --- gw --- [ S2 ]
#   ws3 --/                          \-- ext2  (118.1.0.20, and the controller)
#
# Each segment has a switch of its own, and no port of one is a port of the
# other. The only path from inside to outside is therefore through the gateway,
# which is what makes a capture taken there a complete record of what the
# workstations send out.
#
# The gateway forwards and does not translate addresses, so every packet crossing
# it still carries the workstation's own source address.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$GW_CTN"; then
    echo "Lab already spawned ($GW_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# The learner's whole answer is an nftables chain at the forward hook inside the
# gateway, and Part 5's allowlist matches on connection state. Registering a base
# chain needs the nf_tables machinery available in the container's namespace, and
# a connection-state match needs nf_conntrack; autoloading either needs privilege
# in the initial namespace, which a rootless daemon's containers do not have. On
# a host where nothing has loaded them, the learner's first `nft add table` would
# fail halfway through Part 3 with an error they have no way to interpret. Fail
# here instead, with the reason.
log "checking this host can register an nftables forward chain inside a container"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        "nft add table inet nftprobe \
         && nft 'add chain inet nftprobe c { type filter hook forward priority filter ; policy accept ; }' \
         && nft add rule inet nftprobe c ct state established accept" \
        >/dev/null 2>&1; then
    echo "this host cannot register an nftables forward chain with a connection-state" >&2
    echo "match inside a container. Parts 3 to 5 need one. The nf_tables," >&2
    echo "nft_chain_filter and nf_conntrack modules must be loaded on the host; any" >&2
    echo "machine already running Docker networking normally has them." >&2
    exit 1
fi

# Every container is given an explicit command, which is what stops the base
# image's default CMD (`sshd -D -e`) from running. No machine in this lab runs
# sshd, and a stray listener on 22 would put a service on a port that has nothing
# to do with the lab into every capture the learner takes.
IDLE_CMD=(sleep infinity)

# --init everywhere. PID 1 would otherwise be `sleep infinity`, which never calls
# wait(), and every machine in this lab forks something short-lived on a timer:
# each curl the traffic generators run, each request the controller answers.
# Without docker-init they accumulate as zombies for as long as the lab is up.

# ip_forward is set at creation rather than by default_config/gw.sh, because
# Docker mounts /proc/sys read-only in an unprivileged container. It is set on
# the gateway and explicitly to 0 everywhere else, because "only the gateway
# forwards" is a fact the lab is built on and a reader of this file should not
# have to know what the default is to find it.
log "starting gateway $GW_CTN (two segments, forwarding on, no filtering)"
docker run -d --name "$GW_CTN" --network=none --init \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=1 \
    --hostname gw \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

for w in "${WORKSTATIONS[@]}"; do
    ctn="$( ctn_of "$w" )"
    log "starting workstation $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 \
        --hostname "$w" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

for e in ext1 ext2; do
    ctn="$( ctn_of "$e" )"
    log "starting outside host $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 \
        --hostname "$e" \
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
    local ta="vc${i}a" tb="vc${i}b" pid
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    pid="$( docker inspect -f '{{.State.Pid}}' "$4" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$3"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$3" up
    docker exec "$4" ovs-vsctl add-port "$BR" "$3" >/dev/null
}

log "wiring inside: $GW_CTN($GW_INSIDE_IF) -> $SW_IN_CTN port $( sw_port_of gwlan )"
wire_to_switch "$GW_CTN" "$GW_INSIDE_IF" "$( sw_port_of gwlan )" "$SW_IN_CTN"
for w in "${WORKSTATIONS[@]}"; do
    log "wiring inside: $( ctn_of "$w" )($WS_IF) -> $SW_IN_CTN port $( sw_port_of "$w" )"
    wire_to_switch "$( ctn_of "$w" )" "$WS_IF" "$( sw_port_of "$w" )" "$SW_IN_CTN"
done

log "wiring outside: $GW_CTN($GW_OUTSIDE_IF) -> $SW_OUT_CTN port $( sw_port_of gwext )"
wire_to_switch "$GW_CTN" "$GW_OUTSIDE_IF" "$( sw_port_of gwext )" "$SW_OUT_CTN"
for e in ext1 ext2; do
    log "wiring outside: $( ctn_of "$e" )($EXT_IF) -> $SW_OUT_CTN port $( sw_port_of "$e" )"
    wire_to_switch "$( ctn_of "$e" )" "$EXT_IF" "$( sw_port_of "$e" )" "$SW_OUT_CTN"
done

# Apply the per-device starter configs in the order lib.sh defines: the outside
# services first so there is something to fetch, then the gateway that routes to
# them, then the workstations, whose traffic generators start last and
# immediately have somewhere to send traffic.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. The network has been running for a few seconds; give it a minute"
log "before the first capture so there is something in it."
log "Check it with:  $LAB_DIR/scripts/status.sh"
