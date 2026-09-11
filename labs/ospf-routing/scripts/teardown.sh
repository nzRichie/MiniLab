#!/usr/bin/env bash
# Remove the lab. `docker rm -f` on each container also deletes its veth peers, so
# every interface and every netem qdisc goes with it. Scoped to THIS lab only
# (every container name carries the ${LAB_FILTER} tag) -- deliberately does NOT
# call platform/cleanup/cleanup.sh, which wipes the whole mini-internet.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[teardown] removing lab containers"
mapfile -t ctns < <(docker ps -a --format '{{.Names}}' | grep -- "$LAB_FILTER" || true)
if [ "${#ctns[@]}" -gt 0 ]; then
    docker rm -f "${ctns[@]}" >/dev/null 2>&1 || true
fi

# The wiring helper is normally already gone (spawn stops it through an EXIT trap),
# and it carries the same tag so it is caught above; this is belt-and-braces for an
# interrupted spawn. There is no host state to clean: every veth lived inside a
# container namespace, and there are no netns symlinks, because the helper is the
# only place one was ever made.
docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true

echo "[teardown] done"
