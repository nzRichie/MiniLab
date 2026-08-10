#!/usr/bin/env bash
# Spawn the source-spoofing / reflection lab: one forwarding router between two
# subnets, an attacker on the customer edge, and a victim + two reflectors (DNS,
# NTP) on the core. Self-contained — drives docker + the veth/OVS primitives
# directly, WITHOUT the full platform/startup.sh pipeline (proposal RQ1).
#
# Layer 3, so the fabric is not one flat bridge:
#   attacker --(point-to-point veth)-- router --(OVS switch S1)-- victim/dns/ntp
# The router's customer-facing interface (cust) is the ingress point the defence
# guards; the core hosts share one switched segment behind it.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$SW_CTN"; then
    echo "Lab already spawned ($SW_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

# Build/pull the images this lab runs on before anything needs them.
ensure_images

# 1. Containers (no data-plane network; the veth links + OVS bridge are the only
#    fabric).
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

# The router runs privileged so /proc/sys/net is writable: the learner turns on
# uRPF (rp_filter) at runtime, which a NET_ADMIN-only container cannot do (Docker
# mounts /proc/sys read-only there). ip_forward is set at creation so it forwards
# from the first packet.
log "starting router $ROUTER_CTN (privileged, forwarding)"
docker run -d --name "$ROUTER_CTN" --network=none \
    --privileged --sysctl net.ipv4.ip_forward=1 --hostname router \
    "$HOST_IMAGE" >/dev/null

for h in "${CORE_HOSTS[@]}" attacker; do
    ctn="$(ctn_of "$h")"
    log "starting host $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN --hostname "$h" \
        "$HOST_IMAGE" >/dev/null
done

# 2. Create the OVS bridge on the switch for the core segment (mirrors the L2
#    labs). Single switch, no loops, so STP stays OFF (it would hold ports in
#    listening/learning for ~15-30s and delay the first packet).
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

# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else. helper_stop
# is trapped so the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0

# Put one end of a fresh veth pair into a container and rename it.
plug() {
    local ctn="$1" want_if="$2" tmp="$3"
    local pid
    pid="$(docker inspect -f '{{.State.Pid}}' "$ctn")"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
    echo "$pid"
}

# 3a. Customer edge: a point-to-point veth between attacker and router (no switch,
#     no bridge — just the two ends). This is the link the defence inspects.
wire_point_to_point() {
    local ctnA="$1" ifA="$2" ctnB="$3" ifB="$4"
    i=$((i + 1))
    local ta="vp${i}a" tb="vp${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$ctnA" "$ifA" "$ta" >/dev/null
    plug "$ctnB" "$ifB" "$tb" >/dev/null
}
log "wiring customer edge: $ATTACKER_CTN($ATT_IF) <-> $ROUTER_CTN($R_CUST_IF)"
wire_point_to_point "$ATTACKER_CTN" "$ATT_IF" "$ROUTER_CTN" "$R_CUST_IF"

# 3b. Core segment: the router's core interface and each core host attach to br0.
wire_to_switch() {
    local ctn="$1" host_if="$2" sw_port="$3"
    i=$((i + 1))
    local ta="vh${i}a" tb="vh${i}b" spid
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$ctn" "$host_if" "$ta" >/dev/null
    spid="$(docker inspect -f '{{.State.Pid}}' "$SW_CTN")"
    helper ip link set "$tb" netns "$spid"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$tb" name "$sw_port"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$sw_port" up
    docker exec "$SW_CTN" ovs-vsctl add-port br0 "$sw_port" >/dev/null
}
log "wiring core: $ROUTER_CTN($R_CORE_IF) -> $SW_CTN (port $(sw_port_of router))"
wire_to_switch "$ROUTER_CTN" "$R_CORE_IF" "$(sw_port_of router)"
for h in "${CORE_HOSTS[@]}"; do
    log "wiring core: $(ctn_of "$h")($HOST_IF) -> $SW_CTN (port $(sw_port_of "$h"))"
    wire_to_switch "$(ctn_of "$h")" "$HOST_IF" "$(sw_port_of "$h")"
done

# 4. Apply the per-device starter configs (router first so forwarding is up before
#    anything crosses it; reflectors before the victim; attacker last).
for d in "${DEVICES[@]}"; do
    ctn="$(ctn_of "$d")"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. Check it with:  $LAB_DIR/scripts/status.sh"
