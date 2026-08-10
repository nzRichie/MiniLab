#!/usr/bin/env bash
# Spawn the STP root-bridge-takeover lab: three OVS switches in a ring, the victim
# behind S2, the gateway behind S3, and a dual-homed attacker whose second link
# starts DOWN. Self-contained - drives docker + the veth/OVS primitives directly,
# WITHOUT the full platform/startup.sh pipeline (proposal RQ1).
#
#            S1  (intended root, priority 4096)
#           /  \
#         S2 -- S3
#         |      |
#      victim  gateway
#         \      /
#          attacker      link A (to S2) up, link B (to S3) down until Part 2
#
# The ring is what gives the spanning tree something to decide: STP elects S1 and
# blocks exactly one port to break the loop. The attacker's second link is left
# down so Part 1 is genuinely single-homed and raising it is a step the learner
# takes and can watch.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

# Open vSwitch is NOT required on the host: every ovs-vsctl call in this lab runs
# inside a switch container, whose image ships OVS. Docker reachability is the
# real prerequisite, and it covers an unreachable daemon as well as a stopped one.
command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and can this account reach it? (try: docker info)" >&2
    exit 1
}

if docker ps -a --format '{{.Names}}' | grep -qx "$SW1_CTN"; then
    echo "Lab already spawned ($SW1_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# 1. Containers (no data-plane network; the veth links + OVS bridges are the only
#    fabric).
for sw in "${SWITCHES[@]}"; do
    sw_ctn="$(ctn_of "$sw")"
    log "starting switch $sw_ctn"
    docker run -d --name "$sw_ctn" --network=none \
        --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$sw" \
        "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null
done

for h in "${HOSTS[@]}"; do
    ctn="$(ctn_of "$h")"
    log "starting host $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN --hostname "$h" \
        "$HOST_IMAGE" sleep infinity >/dev/null
done

# 2. One OVS bridge per switch. STP is left OFF here and switched on by each
#    switch's starter config, after every port exists: enabling it once at the end
#    means the tree converges a single time instead of re-converging on each new
#    port.
for sw in "${SWITCHES[@]}"; do
    sw_ctn="$(ctn_of "$sw")"
    log "waiting for Open vSwitch in $sw_ctn"
    for _ in $(seq 1 40); do
        if docker exec "$sw_ctn" ovs-vsctl show >/dev/null 2>&1; then break; fi
        sleep 0.5
    done
    log "creating bridge br0 on $sw_ctn"
    docker exec "$sw_ctn" ovs-vsctl \
        -- add-br br0 \
        -- set bridge br0 stp_enable=false \
        -- set-fail-mode br0 standalone >/dev/null
done

# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else. helper_stop
# is trapped so the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0

# Put one end of a fresh veth pair into a container's netns and rename it.
plug() {
    local ctn="$1" want_if="$2" tmp="$3" pid
    pid="$(docker inspect -f '{{.State.Pid}}' "$ctn")"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}

# One veth pair between two containers, with the interface name each side wants.
link() {   # <ctnA> <ifA> <ctnB> <ifB>
    i=$((i + 1))
    local ta="vs${i}a" tb="vs${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    plug "$3" "$4" "$tb"
}

# 3a. The ring: three inter-switch links, each end named after the switch opposite.
log "wiring the ring: $SW1 == $SW2 == $SW3 == $SW1"
link "$SW1_CTN" "$(sw_port_of "$SW2")" "$SW2_CTN" "$(sw_port_of "$SW1")"
link "$SW2_CTN" "$(sw_port_of "$SW3")" "$SW3_CTN" "$(sw_port_of "$SW2")"
link "$SW1_CTN" "$(sw_port_of "$SW3")" "$SW3_CTN" "$(sw_port_of "$SW1")"

# 3b. The hosts. The attacker gets TWO links, one into each of the switches that
#     carry the victim and the gateway; its second NIC is taken down by its own
#     starter config, so the lab starts with a single-homed attacker.
log "wiring victim -> $SW2, gateway -> $SW3, attacker -> $SW2 and $SW3"
link "$VICTIM_CTN"   "$VICTIM_IF"    "$SW2_CTN" "$VICTIM_PORT"
link "$GATEWAY_CTN"  "$GATEWAY_IF"   "$SW3_CTN" "$GATEWAY_PORT"
link "$ATTACKER_CTN" "$ATTACKER_IF_A" "$SW2_CTN" "$ATT_PORT_S2"
link "$ATTACKER_CTN" "$ATTACKER_IF_B" "$SW3_CTN" "$ATT_PORT_S3"

# 3c. Add every switch-side end to that switch's bridge.
for p in "$(sw_port_of "$SW2")" "$(sw_port_of "$SW3")"; do
    docker exec "$SW1_CTN" ovs-vsctl add-port br0 "$p" >/dev/null
done
for p in "$(sw_port_of "$SW1")" "$(sw_port_of "$SW3")" "$VICTIM_PORT" "$ATT_PORT_S2"; do
    docker exec "$SW2_CTN" ovs-vsctl add-port br0 "$p" >/dev/null
done
for p in "$(sw_port_of "$SW1")" "$(sw_port_of "$SW2")" "$GATEWAY_PORT" "$ATT_PORT_S3"; do
    docker exec "$SW3_CTN" ovs-vsctl add-port br0 "$p" >/dev/null
done

# 4. Apply the per-device starter configs (switches first, so the tree is already
#    converging before a host sends a frame; then the hosts).
for d in "${DEVICES[@]}"; do
    ctn="$(ctn_of "$d")"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up, and the spanning tree is still converging."
log "802.1D holds each port in listening then learning for one forward delay"
log "(${FORWARD_DELAY}s each), so give it ~$(( FORWARD_DELAY * 2 + 5 ))s before the first ping succeeds."
log "Check it with:  $LAB_DIR/scripts/status.sh"
