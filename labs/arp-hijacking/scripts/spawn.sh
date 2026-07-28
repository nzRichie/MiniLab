#!/usr/bin/env bash
# Spawn the ARP-hijacking lab: one OVS switch + attacker/victim/gateway hosts on a
# single flat broadcast domain. Self-contained — drives docker + the veth/OVS
# primitives directly, WITHOUT the full platform/startup.sh pipeline (proposal RQ1).
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

# Open vSwitch is NOT required on the host: every ovs-vsctl call in this lab runs
# inside the switch container, whose image ships OVS. Docker reachability is the
# real prerequisite, and it covers group membership as well as a stopped daemon.
command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and are you in the 'docker' group?" >&2
    exit 1
}

if docker ps -a --format '{{.Names}}' | grep -qx "$SW_CTN"; then
    echo "Lab already spawned ($SW_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

# Build/pull the images this lab runs on before anything needs them.
ensure_images

# 1. Containers (no data-plane network; the OVS bridge is the only fabric).
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" >/dev/null

for h in "${HOSTS[@]}"; do
    ctn="$(ctn_of "$h")"
    log "starting host $ctn"
    # IP forwarding is set here (not via in-container `sysctl -w`, which fails
    # because Docker mounts /proc/sys read-only). Enabling it on every host is
    # harmless on this flat LAN and lets the attacker relay a transparent MITM.
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=1 --hostname "$h" \
        "$HOST_IMAGE" >/dev/null
done

# 2. Create the OVS bridge on the switch (mirrors connect_l2_network.sh:70-76, but
#    STP is left OFF: this lab is a single switch with no loops, and STP would hold
#    ports in listening/learning for ~15-30s, delaying the first packet).
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
    i=$((i + 1))
    local ta="vh${i}a" tb="vh${i}b" hpid spid
    hpid="$(docker inspect -f '{{.State.Pid}}' "$host_ctn")"
    spid="$(docker inspect -f '{{.State.Pid}}' "$SW_CTN")"
    helper_bind_netns "$hpid"
    helper_bind_netns "$spid"
    helper ip link add "$ta" type veth peer name "$tb"
    helper ip link set "$ta" netns "$hpid"
    helper ip link set "$tb" netns "$spid"
    helper ip netns exec "$hpid" ip link set dev "$ta" name "$host_if"
    helper ip netns exec "$hpid" ip link set dev "$host_if" up
    helper ip netns exec "$spid" ip link set dev "$tb" name "$sw_port"
    helper ip netns exec "$spid" ip link set dev "$sw_port" up
    docker exec "$SW_CTN" ovs-vsctl add-port br0 "$sw_port" >/dev/null
}

for h in "${HOSTS[@]}"; do
    log "wiring $h -> $SW_CTN (host if $HOST_IF, switch port ${AS}-${h})"
    wire_host_to_switch "$(ctn_of "$h")" "$HOST_IF" "${AS}-${h}"
done

# 4. Apply the per-device starter configs (mirrors BGP_VPN_MPLS/build/build.sh).
for h in "${HOSTS[@]}"; do
    ctn="$(ctn_of "$h")"
    log "configuring $ctn via default_config/${h}.sh"
    docker cp "$LAB_DIR/default_config/${h}.sh" "$ctn:/home/${h}.sh"
    docker exec "$ctn" chmod 755 "/home/${h}.sh"
    docker exec "$ctn" "/home/${h}.sh"
done

log "lab is up. Check it with:  $LAB_DIR/scripts/status.sh"
