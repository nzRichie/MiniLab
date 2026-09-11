#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline, in place. No teardown: the
# containers, the wiring and the addressing all stay, and only the state the
# learner changed goes back.
#
# It re-runs every starter config, which is what makes the reset total:
#
#   web       reinstalls view.php and the documents from the pristine copies,
#             rewrites the web server's configuration without stage 2A's rule,
#             puts the packaged php.ini back without stage 2B's open_basedir,
#             and rewrites the credential file with the shared account
#   db        reloads the schema, drops every account either stage of Part 2
#             could have created, and recreates the one shared account granted
#             from any address
#   reports   rewrites the report job's credential file with the shared account
#   attacker  re-applies its address and leaves the learner's own files alone
#
# After it, all four stages of Part 2 are undone and Part 1 works again from the
# start.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

for ctn in "$WEB_CTN" "$DB_CTN" "$REPORTS_CTN" "$ATTACKER_CTN"; do
    running "$ctn" || {
        echo "$ctn is not running; spawn the lab before resetting it." >&2
        exit 1
    }
done

for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "re-applying default_config/${d}.sh on $ctn"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "baseline restored. Check it with:  $LAB_DIR/scripts/status.sh"
