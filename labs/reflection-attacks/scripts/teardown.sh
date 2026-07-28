#!/usr/bin/env bash
# Remove the lab. `docker rm -f` on each container also deletes its veth peers, so
# the OVS ports and host-side interfaces go with them. Scoped to THIS lab only —
# deliberately does NOT call platform/cleanup/cleanup.sh, which wipes the whole
# mini-internet and deletes groups/.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[teardown] removing lab containers"
docker rm -f "$SW_CTN" "$ROUTER_CTN" "$ATTACKER_CTN" \
    "$VICTIM_CTN" "$DNS_CTN" "$NTP_CTN" 2>/dev/null || true

# The wiring helper is normally already gone (spawn stops it through an EXIT
# trap). Remove it if an interrupted spawn left it behind. Nothing to clean
# under /run/netns: the netns symlinks only ever existed inside the helper.
docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true

echo "[teardown] done"
