#!/usr/bin/env bash
# Return the lab to its clean pre-analysis baseline, in place. No teardown.
#
# Four kinds of state accumulate while somebody works through this lab, and all
# four have to go:
#
#   the gateway's policy      the nftables table the learner wrote, whichever
#                             part they got to
#   the incident's stage      an implant left at stage 2 or 3, and the extra
#                             address on the outside host that stage 3 added
#   the controller's record   the check-in log, so the counts in Status start
#                             from an empty file rather than from yesterday
#   capture files             a few megabytes each in /tmp on the gateway
#
# It re-runs each device's starter config rather than undoing the learner's work
# one piece at a time. Patching a file somebody else has already edited is how a
# reset leaves a machine in a state neither the handout nor the answer key
# describes.
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

log "reset. The gateway has no policy, the incident is back at stage 1, and the"
log "controller's record is empty."
