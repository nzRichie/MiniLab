#!/usr/bin/env bash
# Show what the lab is doing: containers, each switch's per-port VLAN modes, the
# attacker's honest same-VLAN reach (attacker -> peer), and the hop oracle: does a
# double-tagged frame from the attacker land on the VLAN 20 victim? The oracle runs
# the attack for a moment and counts what the victim captures, so the learner reads
# before and after without shelling in. No MATRIX needed; this is self-contained.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${AS}_L2_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

echo "== S1 port VLAN modes (attacker access + trunk to S2) =="
docker exec "$SW1_CTN" sh -c \
    'for p in '"$ATT_PORT $S1_TRUNK_PORT"'; do
        printf "  %-14s vlan_mode=%s tag=%s trunks=%s\n" "$p" \
            "$(ovs-vsctl get port $p vlan_mode 2>/dev/null)" \
            "$(ovs-vsctl get port $p tag 2>/dev/null)" \
            "$(ovs-vsctl get port $p trunks 2>/dev/null)"
    done'
echo "== S2 port VLAN modes (peer + victim access + trunk to S1) =="
docker exec "$SW2_CTN" sh -c \
    'for p in '"$PEER_PORT $VICTIM_PORT $S2_TRUNK_PORT"'; do
        printf "  %-14s vlan_mode=%s tag=%s trunks=%s\n" "$p" \
            "$(ovs-vsctl get port $p vlan_mode 2>/dev/null)" \
            "$(ovs-vsctl get port $p tag 2>/dev/null)" \
            "$(ovs-vsctl get port $p trunks 2>/dev/null)"
    done'
echo

echo "== attacker -> peer (same VLAN 10, across the trunk: the honest control) =="
if docker exec "$ATTACKER_CTN" ping -c1 -W1 "$PEER_IP" >/dev/null 2>&1; then
    echo "  REACHABLE ($ATTACKER_IP -> $PEER_IP)   legitimate same-VLAN traffic works"
else
    echo "  UNREACHABLE ($ATTACKER_IP -> $PEER_IP)   a defence that breaks this is too broad"
fi
echo

echo "== hop oracle: does a double-tagged frame reach the VLAN 20 victim? =="
# Capture ICMP addressed to the victim, fire a few double-tagged frames, count them.
docker exec -d "$VICTIM_CTN" sh -c \
    "tcpdump -n -i $(host_if_of victim) -w /tmp/hop.pcap 'icmp and dst host $VICTIM_IP' >/dev/null 2>&1"
sleep 0.5
docker exec "$ATTACKER_CTN" \
    vlan-double-tag "$(host_if_of attacker)" "$NATIVE_VLAN_BAD" "$VLAN_VICTIM" "$VICTIM_IP" 5 >/dev/null 2>&1 || true
sleep 1
docker exec "$VICTIM_CTN" pkill -f tcpdump 2>/dev/null || true; sleep 0.3
n="$(docker exec "$VICTIM_CTN" sh -c 'tcpdump -nr /tmp/hop.pcap 2>/dev/null | wc -l' | tr -d ' ')"
if [ "${n:-0}" -gt 0 ]; then
    echo "  HOPPED: victim received $n double-tagged frame(s) from VLAN 10 (attack works)"
else
    echo "  BLOCKED: victim received 0 frames (the hop is stopped)"
fi
