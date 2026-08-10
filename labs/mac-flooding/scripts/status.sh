#!/usr/bin/env bash
# Show what the lab is doing: containers, how full S1's MAC table is and which
# port is holding what, whether the gateway's address is still in it, which
# defences are in place, whether honest traffic still passes, and the leak oracle:
# do victim-to-gateway frames reach the attacker's access port?
#
# The port breakdown is the lab's central fact. A healthy S1 holds eleven entries
# on the uplink, one on each access port, and nothing is evicted. A switch under
# attack holds a full table in which the uplink has been squeezed down to roughly
# what the attacker's port holds, and the gateway is no longer in it.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${AS}_L2_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

gmac="$( gateway_mac )"
amac="$( attacker_mac )"
vmac="$( victim_mac )"

echo "== S1's MAC table (the switch under attack) =="
read -r cur max <<<"$( fdb_fill "$SW1_CTN" )"
evicted="$( fdb_evicted "$SW1_CTN" )"
printf '  %-28s %s\n' "entries in use"      "${cur:-?} of ${max:-?}"
printf '  %-28s %s\n' "evicted since boot"  "${evicted:-0}"
if [ "${evicted:-0}" -gt 0 ]; then
    echo "                               (an entry is only evicted when the table is full,"
    echo "                                so any number here means something filled it)"
fi
echo

echo "== which port is holding the table, and how much of it =="
echo "  Open vSwitch evicts from the port holding the MOST entries, so a port is"
echo "  only ever squeezed down to its share, and only a port carrying more than"
echo "  its share has anything to lose."
printf '  %-16s %-8s %s\n' "PORT" "ENTRIES" "WHAT IS BEHIND IT"
printf '  %-16s %-8s %s\n' "$VICTIM_PORT"    "$( fdb_entries_on_port "$SW1_CTN" "$VICTIM_PORT" )"    "the victim, one address"
printf '  %-16s %-8s %s\n' "$ATTACKER_PORT"  "$( fdb_entries_on_port "$SW1_CTN" "$ATTACKER_PORT" )"  "the attacker, one address unless it is flooding"
printf '  %-16s %-8s %s\n' "$S1_UPLINK_PORT" "$( fdb_entries_on_port "$SW1_CTN" "$S1_UPLINK_PORT" )" "everything beyond S2: the gateway and $STAFF_COUNT staff machines ($(( STAFF_COUNT + 1 )) addresses)"
echo

echo "== is the gateway's address still in S1's table? =="
if fdb_has_mac "$SW1_CTN" "$gmac"; then
    echo "  PRESENT ($gmac)"
    echo "          S1 knows which port to send the victim's frames out of"
else
    echo "  MISSING ($gmac)"
    echo "          S1 has no entry for the gateway, so every frame the victim"
    echo "          addresses to it is flooded to every other port, including the"
    echo "          attacker's"
fi
echo

echo "== defences in place on S1 =="
flows="$( docker exec "$SW1_CTN" ovs-ofctl dump-flows br0 2>/dev/null )"
found=0
if printf '%s' "$flows" | grep -q "priority=${PIN_PRIORITY},dl_dst=${gmac}"; then
    hits="$( printf '%s' "$flows" | grep "dl_dst=${gmac}" \
             | sed -n 's/.*n_packets=\([0-9]*\).*/\1/p' | head -1 )"
    echo "  static forwarding entry for the gateway: APPLIED (${hits:-0} frames forwarded by it)"
    found=1
fi
if printf '%s' "$flows" | grep -q "priority=${DROP_PRIORITY},in_port=.*actions=drop"; then
    dropped="$( printf '%s' "$flows" | grep 'actions=drop' | sed -n 's/.*n_packets=\([0-9]*\).*/\1/p' | head -1 )"
    echo "  port security on the attacker's access port: APPLIED (${dropped:-0} frames dropped)"
    found=1
fi
if docker exec "$SW1_CTN" ovs-appctl fdb/show br0 2>/dev/null | grep -q 'static'; then
    echo "  a static entry added with fdb/add is present, for now: it is exempt from"
    echo "  ageing but not from eviction, so a flood will take it"
    found=1
fi
[ "$found" = 0 ] && echo "  none: S1 accepts any source address on any port and learns from all of them"
echo

echo "== honest traffic (what any defence must not break) =="
if docker exec "$VICTIM_CTN" ping -c2 -W1 "$GATEWAY_IP" >/dev/null 2>&1; then
    echo "  victim -> gateway    REACHABLE ($VICTIM_IP -> $GATEWAY_IP)"
else
    echo "  victim -> gateway    UNREACHABLE ($VICTIM_IP -> $GATEWAY_IP)"
fi
if docker exec "$VICTIM_CTN" ping -c2 -W1 "$( staff_ip 7 )" >/dev/null 2>&1; then
    echo "  victim -> staff07    REACHABLE ($VICTIM_IP -> $( staff_ip 7 ))"
else
    echo "  victim -> staff07    UNREACHABLE ($VICTIM_IP -> $( staff_ip 7 ))"
fi
if docker exec "$ATTACKER_CTN" ping -c2 -W1 "$GATEWAY_IP" >/dev/null 2>&1; then
    echo "  attacker -> gateway  REACHABLE (a defence that cuts the host off entirely is too blunt)"
else
    echo "  attacker -> gateway  UNREACHABLE (the access port carries no traffic at all)"
fi
echo

echo "== leak oracle: do the victim's frames to the gateway reach the attacker? =="
echo "  Counting frames on $ATTACKER_IF whose DESTINATION is the gateway's address"
echo "  ($gmac), which is traffic the attacker has no business receiving."
n="$( attacker_sees )"
if leaking "$n"; then
    echo "  LEAKING: the attacker captured ${n} of the victim's ${LEAK_PROBES} frames to the gateway"
    echo "           S1 has no table entry for the gateway, so it is flooding them"
else
    echo "  CONTAINED: the attacker captured ${n} of the victim's ${LEAK_PROBES} frames to the gateway"
    if [ "${n:-0}" -gt 0 ]; then
        echo "           a frame or two is the first exchange after a table change, which is"
        echo "           flooded whatever else is going on, not interception"
    fi
fi
