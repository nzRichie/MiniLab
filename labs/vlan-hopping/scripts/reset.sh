#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline WITHOUT tearing it down: stop any
# running attack, undo any learner defence on the switches, remove the attacker's
# VLAN subinterface from the single-tag attempt, flush neighbour caches, and
# re-apply the starter configs (which restore the vulnerable OVS port modes). A
# learner who broke the lab is back at the starting line.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping any active attack + capture on the attacker and victim"
# The handout drives the attack by hand with scapy; vlan-double-tag is the baseline
# one-shot. Stop whichever the learner used, plus any capture.
docker exec "$ATTACKER_CTN" pkill -f vlan-double-tag 2>/dev/null || true
docker exec "$ATTACKER_CTN" pkill -f scapy           2>/dev/null || true
docker exec "$ATTACKER_CTN" pkill python3            2>/dev/null || true
docker exec "$VICTIM_CTN"   pkill -f tcpdump         2>/dev/null || true

echo "[reset] removing the attacker's VLAN subinterface (single-tag attempt), if any"
docker exec "$ATTACKER_CTN" ip link del "$(host_if_of attacker).${VLAN_VICTIM}" 2>/dev/null || true

echo "[reset] flushing neighbour caches on all hosts"
for h in "${HOSTS[@]}"; do
    docker exec "$(ctn_of "$h")" ip neigh flush all 2>/dev/null || true
done

echo "[reset] re-applying starter configs (restores the vulnerable switch VLAN modes)"
# Switches first so the ports carry VLANs again before hosts speak; the S1/S2
# starter scripts overwrite whatever port modes the learner changed.
for d in "${DEVICES[@]}"; do
    docker exec "$(ctn_of "$d")" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] baseline restored"
