#!/usr/bin/env bash
# Spawn the command injection and containment lab: an appliance and the
# operator's workstation on an inside segment, a gateway, and the upstream
# monitor and the attacker's machine on an outside segment. Self-contained --
# drives docker + the veth primitives directly, WITHOUT the full
# platform/startup.sh pipeline.
#
#   web ----\                          /-- mon        (120.1.0.20)
#            [ S1 ] --- gw --- [ S2 ]-
#   ops ----/                          \-- attacker   (120.1.0.66)
#
# Each segment has a switch of its own, and no port of one is a port of the
# other. The only path from the appliance to the attacker's listener is
# therefore through the gateway, which is what makes the gateway the one place
# Part 2C's egress allowlist can be enforced.
#
# The gateway forwards and does not translate addresses, so every packet the
# appliance originates still carries the appliance's own address when the
# allowlist sees it.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

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

# Part 2C registers an nftables chain at the forward hook with a connection-state
# match. Registering a base chain needs the nf_tables machinery in the
# container's namespace and the state match needs nf_conntrack; autoloading
# either needs privilege in the initial namespace, which a rootless daemon's
# containers do not have. Fail here with the reason rather than halfway through
# Part 2C with an error the learner would read as their own mistake.
log "checking this host can register an nftables forward chain inside a container"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        "nft add table inet nftprobe \
         && nft 'add chain inet nftprobe c { type filter hook forward priority filter ; policy accept ; }' \
         && nft add rule inet nftprobe c ct state established accept" \
        >/dev/null 2>&1; then
    echo "this host cannot register an nftables forward chain with a connection-state" >&2
    echo "match inside a container. Part 2C needs one. The nf_tables, nft_chain_filter" >&2
    echo "and nf_conntrack modules must be loaded on the host; any machine already" >&2
    echo "running Docker networking normally has them." >&2
    exit 1
fi

# Every container is given an explicit command so the base image's default CMD
# (sshd -D -e) does not run: no machine in this lab runs sshd, and a stray
# listener on 22 has nothing to do with the lab.
IDLE_CMD=(sleep infinity)

# --init everywhere: PID 1 is `sleep infinity`, which never reaps, and lighttpd,
# every CGI it runs, and the attacker's listener all fork children. ip_forward is
# set at creation because Docker mounts /proc/sys read-only in an unprivileged
# container; it is on for the gateway and explicitly off everywhere else.
log "starting gateway $GW_CTN (two segments, forwarding on, no filtering yet)"
docker run -d --name "$GW_CTN" --network=none --init \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=1 "${PING_SYSCTL[@]}" \
    --hostname gw \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

for h in "${INSIDE_HOSTS[@]}"; do
    ctn="$( ctn_of "$h" )"
    log "starting inside host $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 "${PING_SYSCTL[@]}" \
        --hostname "$h" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

for h in "${OUTSIDE_HOSTS[@]}"; do
    ctn="$( ctn_of "$h" )"
    log "starting outside host $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 "${PING_SYSCTL[@]}" \
        --hostname "$h" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# The two switches. --cap-add=ALL minus SYS_RESOURCE is what the mini-internet's
# own switch containers run with; ovs-vswitchd needs most of it, and SYS_RESOURCE
# is dropped because raising RLIMIT_MEMLOCK is what fails in a user namespace.
for sw in "${SWITCHES[@]}"; do
    ctn="$( ctn_of "$sw" )"
    log "starting switch $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$sw" \
        "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null
done

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
# on the host, so the learner needs docker access and nothing else.
helper_start
trap helper_stop EXIT

i=0

plug() {   # <container> <interface name it should have> <temporary name>
    local ctn="$1" want_if="$2" tmp="$3" pid
    pid="$( docker inspect -f '{{.State.Pid}}' "$ctn" )"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}

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
for h in "${INSIDE_HOSTS[@]}"; do
    log "wiring inside: $( ctn_of "$h" )($LAN_IF) -> $SW_IN_CTN port $( sw_port_of "$h" )"
    wire_to_switch "$( ctn_of "$h" )" "$LAN_IF" "$( sw_port_of "$h" )" "$SW_IN_CTN"
done

log "wiring outside: $GW_CTN($GW_OUTSIDE_IF) -> $SW_OUT_CTN port $( sw_port_of gwext )"
wire_to_switch "$GW_CTN" "$GW_OUTSIDE_IF" "$( sw_port_of gwext )" "$SW_OUT_CTN"
for h in "${OUTSIDE_HOSTS[@]}"; do
    log "wiring outside: $( ctn_of "$h" )($EXT_IF) -> $SW_OUT_CTN port $( sw_port_of "$h" )"
    wire_to_switch "$( ctn_of "$h" )" "$EXT_IF" "$( sw_port_of "$h" )" "$SW_OUT_CTN"
done

# Apply the per-device starter configs in lib.sh order.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. Check it with:  $LAB_DIR/scripts/status.sh"
