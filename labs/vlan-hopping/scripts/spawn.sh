#!/usr/bin/env bash
# Spawn the VLAN-hopping lab: two OVS switches joined by an 802.1Q trunk, the
# attacker on VLAN 10 behind S1, and a benign VLAN 10 peer plus the VLAN 20 victim
# behind S2. Self-contained - drives docker + the veth/OVS primitives directly,
# WITHOUT the full platform/startup.sh pipeline (proposal RQ1).
#
# Two switches, because a double-tagged frame only hops across a switch boundary:
#   attacker --(S1)== trunk (native VLAN 10) ==(S2)-- victim(VLAN 20) / peer(VLAN 10)
# S1 strips the outer tag on the trunk's native-VLAN egress; S2 parses the inner
# tag fresh and delivers it. The per-port VLAN modes (the vulnerable baseline) are
# applied by default_config/S1.sh and S2.sh after the ports exist.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$SW1_CTN"; then
    echo "Lab already spawned ($SW1_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

# Build/pull the images this lab runs on before anything needs them.
ensure_images

# 1. Containers (no data-plane network; the veth links + OVS bridges are the only
#    fabric).
for sw_ctn in "$SW1_CTN" "$SW2_CTN"; do
    log "starting switch $sw_ctn"
    docker run -d --name "$sw_ctn" --network=none \
        --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "${sw_ctn##*_}" \
        "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null
done

for h in "${HOSTS[@]}"; do
    ctn="$(ctn_of "$h")"
    log "starting host $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN --hostname "$h" \
        "$HOST_IMAGE" >/dev/null
done

# 2. Create an OVS bridge on each switch (single-bridge-per-switch, no loops, so STP
#    stays OFF: it would hold ports in listening/learning for ~15-30s and delay the
#    first frame).
for sw_ctn in "$SW1_CTN" "$SW2_CTN"; do
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

# 3a. Wire each host to its switch: host-side NIC named <AS>-<SW>, switch-side OVS
#     port named <AS>-<host> (inlined equivalent of connect_one_l2_host).
wire_host_to_switch() {
    local host_ctn="$1" host_if="$2" sw_ctn="$3" sw_port="$4"
    i=$((i + 1))
    local ta="vh${i}a" tb="vh${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$host_ctn" "$host_if" "$ta"
    plug "$sw_ctn"   "$sw_port" "$tb"
    docker exec "$sw_ctn" ovs-vsctl add-port br0 "$sw_port" >/dev/null
}
for h in "${HOSTS[@]}"; do
    sw_ctn="$(ctn_of "$(sw_of "$h")")"
    log "wiring $h -> $(sw_of "$h") (host if $(host_if_of "$h"), switch port $(sw_port_of "$h"))"
    wire_host_to_switch "$(ctn_of "$h")" "$(host_if_of "$h")" "$sw_ctn" "$(sw_port_of "$h")"
done

# 3b. Wire the trunk: a veth pair between the two switch containers, each end added
#     to that switch's br0. VLAN modes on these ports are set by default_config.
wire_switch_trunk() {
    i=$((i + 1))
    local ta="vt${i}a" tb="vt${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$SW1_CTN" "$S1_TRUNK_PORT" "$ta"
    plug "$SW2_CTN" "$S2_TRUNK_PORT" "$tb"
    docker exec "$SW1_CTN" ovs-vsctl add-port br0 "$S1_TRUNK_PORT" >/dev/null
    docker exec "$SW2_CTN" ovs-vsctl add-port br0 "$S2_TRUNK_PORT" >/dev/null
}
log "wiring trunk: $SW1_CTN($S1_TRUNK_PORT) == $SW2_CTN($S2_TRUNK_PORT)"
wire_switch_trunk

# 4. Apply the per-device starter configs (switches first, so the VLAN plumbing is
#    in place before any host sends a frame; then the hosts).
for d in "${DEVICES[@]}"; do
    ctn="$(ctn_of "$d")"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. Check it with:  $LAB_DIR/scripts/status.sh"
