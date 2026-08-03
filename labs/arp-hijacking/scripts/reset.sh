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

echo "[reset] removing any OVS ARP-inspection flows (back to plain learning)"
# del-flows on its own is NOT a restore: it also deletes the NORMAL rule the
# bridge was created with, and ovs-vswitchd does not put it back while the bridge
# exists, so br0 is left matching nothing and dropping every frame. Re-adding a
# priority-0 NORMAL rule is what returns it to a learning switch.
docker exec "$SW_CTN" ovs-ofctl del-flows br0 2>/dev/null || true
docker exec "$SW_CTN" ovs-ofctl add-flow br0 "priority=0,actions=NORMAL" 2>/dev/null || true

echo "[reset] flushing ARP caches on all hosts"
# flush drops learned entries; `ip neigh del` is needed as well because a
# PERMANENT entry from the static-ARP defence survives a flush.
for h in "${HOSTS[@]}"; do
    ctn="$(ctn_of "$h")"
    docker exec "$ctn" sh -c 'ip -4 neigh show | while read -r ip rest; do
        ip neigh del "$ip" dev '"$HOST_IF"' 2>/dev/null || true
    done' 2>/dev/null || true
    docker exec "$ctn" ip neigh flush all 2>/dev/null || true
done

echo "[reset] re-applying starter configs"
for h in "${HOSTS[@]}"; do
    docker exec "$(ctn_of "$h")" "/home/${h}.sh" 2>/dev/null || true
done

echo "[reset] baseline restored"
