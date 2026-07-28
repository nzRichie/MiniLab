#!/usr/bin/env bash
# Show what the lab is doing: containers, per-host addressing, and the victim's
# leased default gateway — the self-contained oracle. The gateway the victim
# trusts is the single fact that decides whether the rogue took over.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${AS}_L2_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

for h in "${HOSTS[@]}"; do
    ctn="$(ctn_of "$h")"
    echo "== $h ($ctn) =="
    docker exec "$ctn" ip -4 -brief addr show "$HOST_IF" 2>/dev/null \
        | sed 's/^/  addr: /' || echo "  (no $HOST_IF)"
    gw="$(docker exec "$ctn" ip route show default 2>/dev/null | awk '{print $3}')"
    echo "  default gateway: ${gw:-<none>}"
    echo
done

echo "== oracle: victim's leased default gateway =="
vgw="$(docker exec "$VICTIM_CTN" ip route show default 2>/dev/null | awk '{print $3}')"
if [ "$vgw" = "$SERVER_IP" ]; then
    echo "  LEGIT  — victim trusts the real server ($SERVER_IP)"
elif [ "$vgw" = "$ATTACKER_IP" ]; then
    echo "  ROGUE  — victim's gateway is the ATTACKER ($ATTACKER_IP)"
elif [ -z "$vgw" ]; then
    echo "  NO LEASE — victim has no default gateway (pool drained, or blocked)"
else
    echo "  OTHER  — victim's gateway is $vgw"
fi
