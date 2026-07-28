#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline WITHOUT tearing it down: stop any
# running attack, drop the defence the learner added on the router, re-apply the
# starter configs (which also restart the reflectors and reset rp_filter to off),
# and flush neighbour caches. A learner who broke the lab is back at the start.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping any attack traffic on the attacker"
# The handout drives the attack by hand (nping for direct spoofing, scapy/reflect
# for reflection). Stop whichever the learner used, plus any capture.
docker exec "$ATTACKER_CTN" pkill -f nping   2>/dev/null || true
docker exec "$ATTACKER_CTN" pkill -f reflect 2>/dev/null || true
docker exec "$ATTACKER_CTN" pkill -f scapy   2>/dev/null || true
docker exec "$ATTACKER_CTN" pkill python3    2>/dev/null || true
for d in "${DEVICES[@]}"; do
    docker exec "$(ctn_of "$d")" pkill -f tcpdump 2>/dev/null || true
done

echo "[reset] removing any source-address-verification defence on the router"
# Drop a learner's nftables ACL and turn reverse-path filtering back off. The
# router's default_config re-does both below; this makes reset safe even if that
# script changes.
docker exec "$ROUTER_CTN" nft delete table ip bcp38 2>/dev/null || true
docker exec "$ROUTER_CTN" sysctl -w net.ipv4.conf."$INGRESS_IF".rp_filter=0 >/dev/null 2>&1 || true

echo "[reset] re-applying starter configs"
for d in "${DEVICES[@]}"; do
    docker exec "$(ctn_of "$d")" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] flushing neighbour caches"
for d in router "${CORE_HOSTS[@]}" attacker; do
    docker exec "$(ctn_of "$d")" ip neigh flush all 2>/dev/null || true
done

echo "[reset] baseline restored"
