#!/usr/bin/env bash
# Return the lab to its clean pre-attempt baseline, in place. No teardown.
#
# It removes the learner's rule file and scratch directory, removes whatever
# they deployed to the scanner, reinstalls the CGI from the image and restarts
# the web server, and restages the two uploads on the client. What it does not
# touch is the corpus and the holdout, which are read-only in their images and
# are the same thirty and ten files on every spawn.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

for role in workstation scanner client holdout; do
    ctn="$( ctn_of "$role" )"
    running "$ctn" || { echo "$ctn is not running; spawn the lab first" >&2; exit 1; }
done

# Each starter config is idempotent and rewrites its machine from scratch, so
# re-running them is the reset.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "re-applying default_config/${d}.sh in $ctn"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "baseline restored: no rule file on the workstation, no database on the scanner."
