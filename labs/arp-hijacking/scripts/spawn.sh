#!/usr/bin/env bash
# Spawn the ARP-hijacking lab: one OVS switch + attacker/victim/gateway hosts on a
# single flat broadcast domain. Self-contained — drives docker + the veth/OVS
# primitives directly, WITHOUT the full platform/startup.sh pipeline (proposal RQ1).
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

# 1. Containers (no data-plane network; the OVS bridge is the only fabric).
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

for h in "${HOSTS[@]}"; do
    ctn="$(ctn_of "$h")"
    log "starting host $ctn"
    # Both sysctls are set here (not via in-container `sysctl -w`, which fails
    # because Docker mounts /proc/sys read-only). Enabling them on every host is
    # harmless on this flat LAN and lets the attacker relay a transparent MITM:
    #   ip_forward=1        relay what the poisoning diverts, so the victim keeps
    #                       working and sees no loss of connectivity.
    #   send_redirects=0    a router that forwards a packet back out the interface
    #                       it arrived on sends the sender an ICMP redirect naming
    #                       the better next hop. Left on, the attacker's own kernel
    #                       announces "100.0.0.10 here, use 100.0.0.1 directly" on
    #                       every relayed packet, printing the attacker's address in
    #                       the victim's own ping output. A real MITM turns it off
    #                       first; here it is off from the start so the handout's
    #                       "the victim sees nothing wrong" is true as written.
    #                       The kernel ORs the `all` and per-interface values, so
    #                       both have to be 0; `default` is what 100-S1 inherits,
    #                       because the helper creates it after this container.
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN \
        --sysctl net.ipv4.ip_forward=1 \
        --sysctl net.ipv4.conf.all.send_redirects=0 \
        --sysctl net.ipv4.conf.default.send_redirects=0 \
        --hostname "$h" \
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
    helper ip link add "$ta" type veth peer name "$tb"
    helper ip link set "$ta" netns "$hpid"
    helper ip link set "$tb" netns "$spid"
    helper nsenter --net="/proc/$hpid/ns/net" ip link set dev "$ta" name "$host_if"
    helper nsenter --net="/proc/$hpid/ns/net" ip link set dev "$host_if" up
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$tb" name "$sw_port"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$sw_port" up
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
