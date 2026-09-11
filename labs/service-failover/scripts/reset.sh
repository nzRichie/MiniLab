#!/usr/bin/env bash
# Return the lab to its clean pre-configuration baseline, in place. No teardown.
#
# Three kinds of state accumulate while somebody works through this lab, and all
# three have to go:
#
#   the proxy's configuration   every section the learner wrote, and the running
#                               daemon that was loaded from it
#   a broken backend            a killed lighttpd, a removed health endpoint, or
#                               an nftables drop rule left over from Part 4
#   a server's runtime state    a backend left in drain or maint through the
#                               runtime API, which survives nothing here because
#                               stopping HAProxy discards it
#
# It re-runs each device's starter config rather than undoing the learner's edits
# one at a time. Patching a file somebody else has already edited is how a reset
# leaves a machine in a state neither the handout nor the answer key describes.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

running "$PROXY_CTN" || {
    echo "The lab is not running ($PROXY_CTN is not up). Spawn it first." >&2
    exit 1
}

log "stopping haproxy on $PROXY_CTN"
hap_stop >/dev/null 2>&1 || true

for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    running "$ctn" || { log "$ctn is not running; skipping"; continue; }
    log "re-applying default_config/${d}.sh on $ctn"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh" >/dev/null
done

log "reset. Both backends serve; the proxy has no frontend or backend and is not running."
