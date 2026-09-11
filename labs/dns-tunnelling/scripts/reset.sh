#!/usr/bin/env bash
# Return the lab to its clean baseline, in place. No teardown.
#
# Three kinds of state accumulate while somebody works through this lab, and all
# three have to go:
#
#   the gateway's policy    whatever the learner wrote in Part 2A, restored to
#                           the starter DNS-only egress policy
#   the resolver's policy   the response policy the learner wrote in Part 2B,
#                           removed by re-applying the starter config
#   the collector's record  the query log and the reassembled files, so the byte
#                           counts in Status start from an empty record
#
# It re-runs each device's starter config rather than undoing the learner's work
# one piece at a time, which is how a reset avoids leaving a machine in a state
# neither the handout nor the answer key describes.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

running "$GW_CTN" || {
    echo "The lab is not running ($GW_CTN is not up). Spawn it first." >&2
    exit 1
}

for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    running "$ctn" || { log "$ctn is not running; skipping"; continue; }
    log "re-applying default_config/${d}.sh on $ctn"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh" >/dev/null
done

log "reset. The gateway has its starter DNS-only egress policy, the resolver has"
log "no response policy, and the collector's record is empty."
