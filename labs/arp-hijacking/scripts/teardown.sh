#!/usr/bin/env bash
# Remove the lab. `docker rm -f` on each container also deletes its veth peers, so
# the OVS ports and host-side interfaces go with them. Scoped to THIS lab only —
# deliberately does NOT call platform/cleanup/cleanup.sh, which wipes the whole
# mini-internet and deletes groups/.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[teardown] removing lab containers"
docker rm -f "$SW_CTN" "$ATTACKER_CTN" "$VICTIM_CTN" "$GATEWAY_CTN" 2>/dev/null || true

echo "[teardown] cleaning dangling netns symlinks"
find /var/run/netns -xtype l -delete 2>/dev/null || true

echo "[teardown] done"
