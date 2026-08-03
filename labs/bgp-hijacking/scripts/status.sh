#!/usr/bin/env bash
# Show what the lab is doing without shelling in: the containers, each router's
# eBGP session count, who originates every prefix in the victim's block at every
# AS, the RPKI plane (what the RIR has signed, what the validator serves, what each
# validating router makes of it), and the data-plane oracle -- what a client's curl
# to the service IP actually reads back.
#
# Origin 1 everywhere and the victim banner everywhere means no hijack; origin 6
# and the impostor banner mark exactly which ASes have been captured.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${LAB_FILTER}" \
    --format 'table {{.Names}}\t{{.Status}}' | sort
echo

echo "== eBGP sessions established (per router) =="
for as in "${ASES[@]}"; do
    est="$( docker exec "$( router_ctn "$as" )" sh -c \
        "vtysh -c 'show ip bgp summary json' 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(\"?/?\"); sys.exit()
p=d.get(\"ipv4Unicast\",{}).get(\"peers\",{})
est=sum(1 for v in p.values() if v.get(\"state\")==\"Established\")
print(f\"{est}/{len(p)}\")'" 2>/dev/null )"
    echo "  AS${as}: ${est:-?} established"
done
echo

# Every prefix either side can put into the table, ordered from the aggregate down
# to the /24 floor. A prefix nobody announces is skipped, so the matrix only ever
# shows what is actually in play.
WATCHED=( "$VICTIM_PREFIX" "${VICTIM_DEAGG_23[@]}" "$HIJACK_SUB23" \
          "${VICTIM_DEAGG_24[@]}" "${HIJACK_SUB24[@]}" )
# de-duplicate while keeping order (the two ladders overlap at 1.0.0.0/23 and /24)
seen=""; PREFIXES=()
for p in "${WATCHED[@]}"; do
    case " $seen " in *" $p "*) continue ;; esac
    seen="$seen $p"; PREFIXES+=("$p")
done

echo "== best-path origin per AS   (1 = victim, 6 = attacker, loc = originated here, - = no route) =="
printf '  %-16s' "prefix"
for as in "${ASES[@]}"; do printf '%-6s' "AS${as}"; done
echo
for p in "${PREFIXES[@]}"; do
    row=""; any=0
    for as in "${ASES[@]}"; do
        o="$( best_path_origin "$( router_ctn "$as" )" "$p" )"
        case "$o" in
            "")    cell="-" ;;
            local) cell="loc"; any=1 ;;
            *)     cell="$o";  any=1 ;;
        esac
        row="${row}$( printf '%-6s' "$cell" )"
    done
    [ "$any" -eq 1 ] && printf '  %-16s%s\n' "$p" "$row"
done
echo

echo "== RPKI: what the RIR has signed =="
if docker ps --format '{{.Names}}' | grep -q "^${RIR_CTN}$"; then
    for spec in "${KRILL_CAS[@]}"; do
        read -r ca _ _ <<<"$spec"
        listing="$( krillc roas list --ca "$ca" 2>/dev/null | tr -d '\r' | grep . )"
        if [ -n "$listing" ]; then
            echo "  ${ca}:"
            printf '%s\n' "$listing" | sed 's/^/    /'
        else
            echo "  ${ca}: no ROAs"
        fi
    done
    echo "  portal: ${KRILL_UI_URL}  (token: ${KRILL_TOKEN})"
else
    echo "  RIR container is not running"
fi
echo

echo "== RPKI: what the validator serves =="
if docker ps --format '{{.Names}}' | grep -q "^${VALIDATOR_CTN}$"; then
    echo "  $( vrp_count ) VRP(s) over RTR on port ${RTR_PORT}:"
    docker exec "$VALIDATOR_CTN" sh -c \
        'wget -q -O - http://127.0.0.1:9556/csv 2>/dev/null | tail -n +2' 2>/dev/null | sed 's/^/    /'
else
    echo "  validator container is not running"
fi
echo

echo "== RPKI: validation state at the routers that have a cache configured =="
for as in "${RPKI_CACHE_ASES[@]}"; do
    conn="$( docker exec "$( router_ctn "$as" )" vtysh -c 'show rpki cache-connection' 2>/dev/null \
             | grep -c 'connected' )"
    if [ "${conn:-0}" -eq 0 ]; then
        echo "  AS${as}: no RPKI cache connected"
        continue
    fi
    echo "  AS${as}: cache connected"
    for p in "${PREFIXES[@]}"; do
        s="$( rpki_state "$( router_ctn "$as" )" "$p" )"
        o="$( best_path_origin "$( router_ctn "$as" )" "$p" )"
        [ -n "$s" ] && printf '    %-16s best origin %-4s -> %s\n' "$p" "${o:--}" "$s"
    done
done
echo

echo "== data-plane oracle: curl ${VICTIM_SVC_IP} from each client =="
captured=()
for as in 2 3 4 5; do
    r="$( docker exec "$( host_ctn "$as" )" curl -s --max-time 3 "http://${VICTIM_SVC_IP}/" 2>/dev/null )"
    echo "  client${as}: ${r:-<no answer>}"
    [ "$r" = "$ATTACKER_BANNER" ] && captured+=("AS${as}")
done
echo

if [ "${#captured[@]}" -eq 0 ]; then
    echo "== verdict: no hijack -- every client reaches the real victim (AS${VICTIM_AS}) =="
else
    echo "== verdict: hijack active -- captured clients: ${captured[*]} =="
fi
