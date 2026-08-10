#!/usr/bin/env bash
# Remove this lab's containers, and nothing else.
#
# Scoped to the 106_L7_LAB_ prefix on purpose: it must never call
# platform/cleanup/cleanup.sh or hard_reset.sh, which wipe the whole
# mini-internet. There is no host network state to clean either, because every
# veth in this lab lives inside a container namespace and goes away with it.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[teardown] removing ${AS}_L7_${DC}_* containers"
mapfile -t ctns < <( docker ps -a --format '{{.Names}}' | grep "^${AS}_L7_${DC}_" || true )

if [ "${#ctns[@]}" -eq 0 ]; then
    echo "[teardown] nothing to remove"
else
    docker rm -f "${ctns[@]}" >/dev/null
    printf '[teardown] removed %s\n' "${ctns[@]}"
fi

# In case an interrupted spawn left the privileged helper behind.
docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true

echo "[teardown] done"
