#!/usr/bin/env bash
# Return the lab to its clean pre-scan baseline WITHOUT tearing it down: stop any
# scan still running, throw away the scan output the learner accumulated, restore
# the telnet account's password in case they changed it after getting in, and
# re-apply the starter configs (which restart all three services). A learner who
# broke the lab, or who wants to re-run Part 1 from nothing, is back at the start.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping any scan or attack still running on the attacker"
for tool in zmap masscan nmap hydra tcpdump telnet; do
    docker exec "$ATTACKER_CTN" pkill -x "$tool" 2>/dev/null || true
done

echo "[reset] clearing the attacker's scan output"
# The handout has the learner build up ips.txt, report files and grepped host
# lists in /root/scan. Wiping them means Part 1 starts from an empty directory,
# so a re-run measures the scan rather than reading the last run's file.
docker exec "$ATTACKER_CTN" sh -c 'rm -rf /root/scan; mkdir -p /root/scan' 2>/dev/null || true

echo "[reset] stopping captures on the target hosts"
for h in "${TARGET_HOSTS[@]}"; do
    docker exec "$(ctn_of "$h")" pkill -x tcpdump 2>/dev/null || true
done

echo "[reset] re-applying starter configs"
# Each service's starter config restarts its daemon, so this also recovers a
# service the learner stopped. telnet.sh resets the shared account's password,
# which matters if they logged in and changed it.
for d in "${DEVICES[@]}"; do
    docker exec "$(ctn_of "$d")" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] flushing neighbour caches"
for d in router "${TARGET_HOSTS[@]}" attacker; do
    docker exec "$(ctn_of "$d")" ip neigh flush all 2>/dev/null || true
done

echo "[reset] baseline restored"
