#!/usr/bin/env bash
# Spawn the MAC-flooding lab: two OVS switches joined by an uplink, the victim and
# the attacker on access ports of S1, and the gateway plus ten staff machines
# behind S2. Self-contained - drives docker + the veth/OVS primitives directly,
# WITHOUT the full platform/startup.sh pipeline (proposal RQ1).
#
#      S1 (access, mac-table-size=16)          S2 (distribution)
#        victim   --+                            +-- gateway 106.0.0.1
#        attacker --+--- uplink ========= uplink-+-- staff x10 (106.0.0.31-.40)
#
# The ten staff machines are what make the attack possible at all. Open vSwitch
# evicts from the port holding the most entries rather than in plain
# least-recently-used order, so a flood on an access port with one host behind it
# only ever evicts its own entries. S1's uplink carries eleven addresses, more
# than its share of a 16-entry table, so that is the port the flood squeezes.
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
# IPv6 is switched off in every container in this lab, and it has to be done here
# at `docker run` rather than in a starter config, for the same read-only
# /proc/sys reason as the host sysctls below. Setting conf.default as well as
# conf.all is what makes it stick: the veths do not exist yet, and a new interface
# takes its settings from conf.default.
#
# It matters because this lab counts MAC addresses. Bringing a veth up makes the
# kernel send IPv6 multicast listener traffic from that netdev, so S1 learns S2's
# own uplink interface as a twelfth address on the uplink port, and it keeps
# re-appearing after a flush. That address belongs to no host in the topology, and
# the lab's whole argument is arithmetic about which addresses are on which port.
IPV6_OFF=( --sysctl net.ipv6.conf.all.disable_ipv6=1
           --sysctl net.ipv6.conf.default.disable_ipv6=1 )

for sw in "${SWITCHES[@]}"; do
    sw_ctn="$(ctn_of "$sw")"
    log "starting switch $sw_ctn"
    docker run -d --name "$sw_ctn" --network=none \
        --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$sw" \
        "${IPV6_OFF[@]}" \
        "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null
done

# Sysctls are set here, at `docker run`, and NOT from inside a starter config,
# because Docker mounts /proc/sys read-only in a container that is not
# --privileged: a `sysctl -w` in default_config/ fails with "Read-only file
# system" and, if its error is swallowed, leaves a setting the lab believes it
# applied and did not. These are namespaced under net.*, so the daemon accepts
# them for a container with a network namespace of its own.
#
# Only the staff container needs them, and it needs them because it is the one
# host here with more than one interface in the same subnet. Both were measured
# failures before they went in:
#   arp_ignore=1    answer an ARP request only for an address configured on the
#                   interface it arrived on. With the default, the kernel answers
#                   for ANY of the ten out of whichever interface the broadcast
#                   reached first, and the victim's ARP cache ends up mapping nine
#                   of the ten staff addresses to the first staff machine's MAC.
#   arp_announce=2  source an ARP request from the address on the sending
#                   interface, so a request out of staff03 says it is staff03.
#   rp_filter=0     accept a reply that arrives on a different interface from the
#                   one the route table would have chosen. The image ships strict
#                   reverse-path filtering (rp_filter=1), and with ten interfaces
#                   on one subnet the route table prefers exactly one of them, so
#                   the echo replies to the other nine were being dropped on
#                   arrival and nine of the ten staff machines could reach nothing.
#                   conf.default is set too, because the ten interfaces do not
#                   exist yet and the kernel takes max(conf.all, conf.<if>).
host_sysctls() {   # <role> -> the --sysctl flags that role needs
    case "$1" in
        staff)   printf '%s\n' --sysctl net.ipv4.conf.all.arp_ignore=1 \
                               --sysctl net.ipv4.conf.all.arp_announce=2 \
                               --sysctl net.ipv4.conf.all.rp_filter=0 \
                               --sysctl net.ipv4.conf.default.rp_filter=0 ;;
        gateway) printf '%s\n' --sysctl net.ipv4.ip_forward=1 ;;
    esac
}

for h in "${HOSTS[@]}"; do
    ctn="$(ctn_of "$h")"
    log "starting host $ctn"
    mapfile -t sysctls < <( host_sysctls "$h" )
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN --hostname "$h" \
        "${IPV6_OFF[@]}" "${sysctls[@]}" \
        "$HOST_IMAGE" sleep infinity >/dev/null
done

# 2. One OVS bridge per switch. No loop in this topology, so STP stays off: it
#    would hold every port in listening then learning for a forward delay each and
#    delay the first frame by half a minute for nothing.
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

# Wire a host NIC to a switch port and add the switch end to that switch's bridge
# (the inlined equivalent of the platform's connect_one_l2_host primitive).
wire_host_to_switch() {   # <host ctn> <host if> <switch ctn> <switch port>
    i=$((i + 1))
    local ta="vh${i}a" tb="vh${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    plug "$3" "$4" "$tb"
    docker exec "$3" ovs-vsctl add-port br0 "$4" >/dev/null
}

# 3a. The two access ports on S1, and the gateway on S2.
log "wiring victim -> $SW1 (host if $VICTIM_IF, switch port $VICTIM_PORT)"
wire_host_to_switch "$VICTIM_CTN" "$VICTIM_IF" "$SW1_CTN" "$VICTIM_PORT"
log "wiring attacker -> $SW1 (host if $ATTACKER_IF, switch port $ATTACKER_PORT)"
wire_host_to_switch "$ATTACKER_CTN" "$ATTACKER_IF" "$SW1_CTN" "$ATTACKER_PORT"
log "wiring gateway -> $SW2 (host if $GATEWAY_IF, switch port $GATEWAY_PORT)"
wire_host_to_switch "$GATEWAY_CTN" "$GATEWAY_IF" "$SW2_CTN" "$GATEWAY_PORT"

# 3b. The ten staff machines. Ten real veth pairs into ten real ports on S2, not
#     ten addresses on one interface: the point of them is that S1's uplink learns
#     ten distinct MAC addresses through it, and a learner reading `fdb/show` has
#     to be able to see them as ten separate entries on separate ports of S2.
log "wiring $STAFF_COUNT staff machines -> $SW2"
for n in $(seq 1 "$STAFF_COUNT"); do
    wire_host_to_switch "$STAFF_CTN" "$(staff_if "$n")" "$SW2_CTN" "$(staff_port "$n")"
done

# 3c. The uplink, each end named after the switch on the other side.
log "wiring uplink: $SW1($S1_UPLINK_PORT) == $SW2($S2_UPLINK_PORT)"
i=$((i + 1))
helper ip link add "vu${i}a" type veth peer name "vu${i}b"
plug "$SW1_CTN" "$S1_UPLINK_PORT" "vu${i}a"
plug "$SW2_CTN" "$S2_UPLINK_PORT" "vu${i}b"
docker exec "$SW1_CTN" ovs-vsctl add-port br0 "$S1_UPLINK_PORT" >/dev/null
docker exec "$SW2_CTN" ovs-vsctl add-port br0 "$S2_UPLINK_PORT" >/dev/null

# 4. Apply the per-device starter configs (switches first, so the MAC table is
#    sized before a host sends a frame; then the hosts, staff last because its
#    keepalive traffic is what fills the uplink's share of the table).
for d in "${DEVICES[@]}"; do
    ctn="$(ctn_of "$d")"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

# 5. Clear both MAC tables, then warm them with the traffic the lab is about, so
#    the baseline a learner reads is the same on every machine and every spawn.
#
#    Without this the table also holds a stray address: bringing a veth up makes
#    the kernel in the switch container send IPv6 multicast listener traffic from
#    that netdev, so S1 learns S2's own uplink interface as a twelfth address on
#    the uplink port. It never sends again and ages out five minutes later, but
#    until it does, a learner counting entries sees 14 where the lab says 13.
#    Flushing after everything is wired drops it, and nothing re-learns it.
log "clearing both MAC tables and warming them with the lab's own traffic"
for sw in "${SWITCHES[@]}"; do
    docker exec "$(ctn_of "$sw")" ovs-appctl fdb/flush br0 >/dev/null 2>&1 || true
done

# The staff keepalives repopulate the ten addresses behind the uplink on their
# own. The gateway is only learned once something talks to it, and the attacker
# only once it sends anything at all, so both are prompted here: that is what
# makes the baseline exactly 11 on the uplink, 1 on the victim's port and 1 on
# the attacker's.
docker exec "$VICTIM_CTN"   ping -c2 -i0.3 -W1 "$GATEWAY_IP" >/dev/null 2>&1 || true
docker exec "$ATTACKER_CTN" ping -c2 -i0.3 -W1 "$GATEWAY_IP" >/dev/null 2>&1 || true

log "waiting for the staff machines' traffic to populate S1's MAC table"
for _ in $(seq 1 30); do
    [ "$( fdb_entries_on_port "$SW1_CTN" "$S1_UPLINK_PORT" )" -gt "$STAFF_COUNT" ] && break
    sleep 1
done

read -r cur max <<<"$( fdb_fill "$SW1_CTN" )"
log "lab is up. S1's MAC table holds ${cur:-?} of ${max:-?} entries,"
log "$( fdb_entries_on_port "$SW1_CTN" "$S1_UPLINK_PORT" ) of them on the uplink to $SW2."
log "Check it with:  $LAB_DIR/scripts/status.sh"
