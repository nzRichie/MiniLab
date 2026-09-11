#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline, in place. No teardown.
#
# Four kinds of state accumulate while somebody works through this lab:
#
#   the filter rules      whatever the learner appended to the INPUT chain,
#                         including Part 3's NFQUEUE rule, which drops every
#                         packet arriving at the server when nothing is reading
#                         the queue
#   Suricata              a running process, in either mode
#   Suricata's config     two edits to /etc/suricata/suricata.yaml and a local
#                         rules file that did not exist at spawn
#   the alert log         fast.log and eve.json, so a count read after a reset
#                         counts what happened after the reset
#
# All four are undone by re-running each device's starter config rather than by
# unpicking the learner's work one piece at a time. suricata.yaml in particular
# has no inverse edit: it is restored from the copy the image took before
# anything touched it.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

running "$SERVER_CTN" || {
    echo "The lab is not running ($SERVER_CTN is not up). Spawn it first." >&2
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

log "reset. The server's filter table is empty, Suricata is not running, its"
log "configuration is back as the package shipped it, and the alert log is gone."
