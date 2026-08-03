#!/usr/bin/env bash
# Remove the lab. `docker rm -f` on each container also deletes its veth peers, so
# every host-side interface goes with it. Scoped to THIS lab only (every container
# name carries the ${LAB_FILTER} tag, including the RIR and the validator) --
# deliberately does NOT call platform/cleanup/cleanup.sh, which wipes the whole
# mini-internet.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[teardown] removing lab containers"
mapfile -t ctns < <(docker ps -a --format '{{.Names}}' | grep -- "$LAB_FILTER" || true)
if [ "${#ctns[@]}" -gt 0 ]; then
    docker rm -f "${ctns[@]}" >/dev/null 2>&1 || true
fi

# The wiring helper is normally already gone (spawn stops it through an EXIT trap),
# and it carries the same tag so it is caught above; this is belt-and-braces for an
# interrupted spawn. No /run/netns to clean: the symlinks only ever lived inside it.
docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true

# The RPKI management bridge is created by spawn and belongs to this lab alone. It
# only removes once its containers are gone, which is why it comes last.
if docker network inspect "$RPKI_NET" >/dev/null 2>&1; then
    echo "[teardown] removing the RPKI management network"
    docker network rm "$RPKI_NET" >/dev/null 2>&1 || true
fi

echo "[teardown] done"
