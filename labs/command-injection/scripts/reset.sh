#!/usr/bin/env bash
# Return the lab to its clean baseline, in place. No teardown.
#
# Four kinds of state accumulate while somebody works through this lab, and all
# four have to go:
#
#   the gateway's ruleset   whatever the learner wrote in Part 2C, removed
#   the appliance's server  the service account and the restart from Part 2A,
#                           undone by rewriting the configuration from scratch
#   the appliance's webroot the ownership and modes from Part 2B, and any second
#                           CGI an attacker left in the directory
#   the attacker's listener whatever a netcat was left holding, and whatever it
#                           had already received
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

log "reset. The page runs as root again, the webroot belongs to svc, the gateway"
log "filters nothing, and the attacker's listener has received nothing."
