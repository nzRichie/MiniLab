#!/usr/bin/env bash
# Return the lab to its clean pre-configuration baseline, in place. No teardown:
# the containers, the wiring and the switch stay exactly as they are, and only
# what the learner wrote is undone.
#
# The whole of the reset is "run every starter config again", because each one
# was written to undo the work that lands on its own machine:
#
#   edge         flushes the ruleset, leaving no base chain at any hook
#   bastion      restores sshd_config from the pristine copy, empties the jump
#                account's ~/.ssh, restarts sshd
#   app          the same, plus removes the copy of db's operator key
#   db           the same, plus removes the copy of app's operator key, and
#                rebuilds the reporting account with no key
#   workstation  removes ~/.ssh entirely: no key pairs, no client configuration
#
# Keeping the undo beside the setup is deliberate. A reset that patched files
# from here would have to know what the starter config wrote AND what the learner
# wrote on top of it, and the two would drift apart the first time either changed.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

docker ps --format '{{.Names}}' | grep -qx "$EDGE_CTN" || {
    echo "The lab is not running ($EDGE_CTN is not up). Spawn it first." >&2
    exit 1
}

for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "re-applying default_config/${d}.sh on $ctn"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "baseline restored: every machine in the site is reachable from outside it again."
log "Check it with:  $LAB_DIR/scripts/status.sh"
