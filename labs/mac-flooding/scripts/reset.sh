#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline WITHOUT tearing it down: stop any
# running flood and capture, drop whatever the learner added to S1's flow table,
# clear the MAC tables, re-apply the starter configs, and wait until the baseline
# the lab is measured against is actually back.
#
# Waiting matters. Clearing the table takes a moment to undo: the ten staff
# keepalives repopulate the uplink's entries within a second, but the gateway's
# entry only comes back when something addresses it, and the attacker's only when
# it sends. Returning before both are learned would hand the learner a table with
# 11 entries and a handout that says 13.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping any flood and capture"
docker exec "$ATTACKER_CTN" pkill -f mac-flood >/dev/null 2>&1 || true
docker exec "$ATTACKER_CTN" pkill python3      >/dev/null 2>&1 || true
for h in "${HOSTS[@]}"; do
    docker exec "$(ctn_of "$h")" pkill -f tcpdump >/dev/null 2>&1 || true
done

echo "[reset] removing any defence the learner applied to S1"
# Everything the learner is told to add goes in the flow table above the default
# NORMAL rule, so clearing the table and putting NORMAL back is a complete undo,
# whichever of the two defences they wrote.
docker exec "$SW1_CTN" ovs-ofctl del-flows br0 >/dev/null 2>&1 || true
docker exec "$SW1_CTN" ovs-ofctl add-flow br0 "priority=0,actions=NORMAL" >/dev/null 2>&1 || true

echo "[reset] clearing both MAC tables and their counters"
for sw in "${SWITCHES[@]}"; do
    sw_ctn="$(ctn_of "$sw")"
    docker exec "$sw_ctn" ovs-appctl fdb/flush br0       >/dev/null 2>&1 || true
    docker exec "$sw_ctn" ovs-appctl fdb/stats-clear br0 >/dev/null 2>&1 || true
done

echo "[reset] flushing neighbour caches on all hosts"
for h in "${HOSTS[@]}"; do
    docker exec "$(ctn_of "$h")" ip neigh flush all >/dev/null 2>&1 || true
done

echo "[reset] re-applying starter configs"
for d in "${DEVICES[@]}"; do
    docker exec "$(ctn_of "$d")" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] warming the table back to its baseline"
docker exec "$VICTIM_CTN"   ping -c2 -i0.3 -W1 "$GATEWAY_IP" >/dev/null 2>&1 || true
docker exec "$ATTACKER_CTN" ping -c2 -i0.3 -W1 "$GATEWAY_IP" >/dev/null 2>&1 || true

# Poll for the state the baseline is defined by: every address behind the uplink
# learned, nothing evicted, and the victim reaching the gateway.
for _ in $(seq 1 40); do
    up="$( fdb_entries_on_port "$SW1_CTN" "$S1_UPLINK_PORT" )"
    ev="$( fdb_evicted "$SW1_CTN" )"
    if [ "${up:-0}" -gt "$STAFF_COUNT" ] && [ "${ev:-0}" -eq 0 ] \
       && docker exec "$VICTIM_CTN" ping -c1 -W1 "$GATEWAY_IP" >/dev/null 2>&1; then
        read -r cur max <<<"$( fdb_fill "$SW1_CTN" )"
        echo "[reset] baseline restored: ${cur} of ${max} entries, ${up} of them on the uplink"
        exit 0
    fi
    sleep 1
done

echo "[reset] the table had not settled after 40s; run status.sh to see where it is" >&2
exit 1
