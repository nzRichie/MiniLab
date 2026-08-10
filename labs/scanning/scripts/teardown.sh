#!/usr/bin/env bash
# Remove the lab. `docker rm -f` on each container also deletes its veth peers, so
# the OVS ports and host-side interfaces go with them. Scoped to THIS lab only —
# deliberately does NOT call platform/cleanup/cleanup.sh, which wipes the whole
# mini-internet and deletes groups/.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[teardown] removing lab containers"
# Selected by the lab's own name prefix rather than by the list in lib.sh, so a
# container this lab started under a name lib.sh no longer knows still goes. The
# target hosts were renamed from web/idle/ftp/telnet to host1..host4 once already,
# and a teardown that reads only the current names leaves the previous run's
# containers holding their veths and their switch ports.
mapfile -t ctns < <( docker ps -aq --filter "name=^${AS}_L4_${DC}_" )
[ "${#ctns[@]}" -gt 0 ] && docker rm -f "${ctns[@]}" >/dev/null 2>&1
true

# The wiring helper is normally already gone (spawn stops it through an EXIT
# trap). Remove it if an interrupted spawn left it behind. Nothing to clean
# under /run/netns: the netns symlinks only ever existed inside the helper.
docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true

echo "[teardown] done"
