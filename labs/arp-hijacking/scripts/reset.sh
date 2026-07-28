#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline WITHOUT tearing it down: stop any
# running attack, drop any defences the learner added, flush ARP caches, re-apply
# the starter configs. A learner who broke the lab is back at the starting line.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping any active poisoning on the attacker"
# The handout drives the attack by hand with nping; arp-poison is the baseline
# one-shot. Stop whichever the learner used.
docker exec "$ATTACKER_CTN" pkill -f nping      2>/dev/null || true
docker exec "$ATTACKER_CTN" pkill -f arp-poison 2>/dev/null || true

echo "[reset] removing any OVS ARP-inspection flows (back to standalone learning)"
docker exec "$SW_CTN" ovs-ofctl del-flows br0 2>/dev/null || true

echo "[reset] flushing ARP caches on all hosts"
for h in "${HOSTS[@]}"; do
    docker exec "$(ctn_of "$h")" ip neigh flush all 2>/dev/null || true
done

echo "[reset] re-applying starter configs"
for h in "${HOSTS[@]}"; do
    docker exec "$(ctn_of "$h")" "/home/${h}.sh" 2>/dev/null || true
done

echo "[reset] baseline restored"
