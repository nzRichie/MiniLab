#!/usr/bin/env bash
# Remove the range. `docker rm -f` on each container also deletes its veth peers,
# so the OVS ports and the interfaces inside each container go with them. Scoped
# to THIS range only: it deliberately does not call platform/cleanup/cleanup.sh,
# which wipes the whole mini-internet and deletes groups/.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[teardown] removing range containers"
# Selected by the range's own name prefix rather than by the list in
# state/topology.env, so a container from a previous seed still goes even after a
# fresh generate has overwritten the list of names.
mapfile -t ctns < <( docker ps -aq --filter "name=^${CTN_PREFIX}" )
[ "${#ctns[@]}" -gt 0 ] && docker rm -f "${ctns[@]}" >/dev/null 2>&1
true

# The wiring helper is normally already gone (spawn stops it through an EXIT
# trap). Remove it if an interrupted spawn left it behind. Nothing to clean under
# /run/netns: the netns symlinks only ever existed inside the helper.
docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true

# The learner's findings and the score marker belong to the range that has just
# been removed, and a later spawn draws a different one. Leaving them would let
# Reveal print a key for a network that is no longer running.
rm -f "$SCORED_MARKER" "$FINDINGS_COPY" "$STATE_DIR/zone.data"

echo "[teardown] done"
