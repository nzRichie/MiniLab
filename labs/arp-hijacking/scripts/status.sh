#!/usr/bin/env bash
# Show what the lab is doing: containers, per-host addressing + ARP caches, and
# victim->gateway reachability (the self-contained oracle; no MATRIX needed).
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${AS}_L2_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

for h in "${HOSTS[@]}"; do
    ctn="$(ctn_of "$h")"
    echo "== $h ($ctn) =="
    docker exec "$ctn" ip -brief addr show "$HOST_IF" 2>/dev/null \
        | sed 's/^/  /' || echo "  (no $HOST_IF)"
    echo "  ARP cache:"
    docker exec "$ctn" ip neigh show 2>/dev/null | sed 's/^/    /'
    echo
done

echo "== victim -> gateway reachability =="
if docker exec "$VICTIM_CTN" ping -c1 -W1 "$GW_IP" >/dev/null 2>&1; then
    echo "  REACHABLE ($VICTIM_IP -> $GW_IP)"
else
    echo "  UNREACHABLE ($VICTIM_IP -> $GW_IP)"
fi
