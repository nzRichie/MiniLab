#!/usr/bin/env bash
# Return the lab to its clean baseline, in place. No teardown.
#
# Three kinds of state accumulate while somebody works through this lab, and all
# three have to go:
#
#   the grants       whatever the learner revoked or granted in Parts 2A and 2B,
#                    put back by dropping and recreating both accounts
#   the ruleset      whatever the learner wrote in Part 2C, removed with the
#                    table it lives in
#   the data         any row an attacker or a learner changed, put back by
#                    reloading the schema
#
# It re-runs each device's starter config rather than undoing the learner's work
# one piece at a time, which is how a reset avoids leaving a machine in a state
# neither the handout nor the answer key describes. The web server is restarted
# too, so a learner who edited an endpoint gets the pristine copy back.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

running "$DB_CTN" || {
    echo "The lab is not running ($DB_CTN is not up). Spawn it first." >&2
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

log "reset. ${APP_USER} holds SELECT on ${DB_NAME}.* and FILE on *.* again, the"
log "database accepts a connection from every host on the segment again, and both"
log "endpoints are back to the copies in the image."
