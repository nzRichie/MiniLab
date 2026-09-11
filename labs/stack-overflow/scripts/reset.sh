#!/usr/bin/env bash
# Return the lab to its clean baseline, in place. No teardown.
#
# Three kinds of state accumulate while somebody works through this lab:
#
#   the appliance's builds   every binary Part 2 compiled, removed, and the
#                            vulnerable build recompiled from the source in
#                            case a stage overwrote it
#   the running service      restarted on the vulnerable build with ASLR off,
#                            whichever build and whichever launch a stage left
#   the service's log        emptied, so the next stack-smashing message a
#                            learner reads is the one they just caused
#
# It re-runs each device's starter config rather than undoing the learner's work
# one piece at a time, which is how a reset avoids leaving a machine in a state
# neither the handout nor the answer key describes.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

running "$SVC_CTN" || {
    echo "The lab is not running ($SVC_CTN is not up). Spawn it first." >&2
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

log "reset. The appliance runs the vulnerable build again, ${BIN_DIR} holds"
log "nothing else, and the service log is empty."
