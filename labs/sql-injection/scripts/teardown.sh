#!/usr/bin/env bash
# Remove this lab's containers and nothing else.
#
# Scoped to the containers named in lib.sh plus the wiring helper. It must never
# call platform/cleanup/cleanup.sh or hard_reset.sh: those wipe the whole
# mini-internet and delete groups/, and this lab is not the only thing that may
# be running on the machine.
#
# There is no host network state to clean. Every veth in this lab lives inside a
# container's network namespace and every OVS port lives inside the switch
# container, so removing the containers removes all of it. The helper is removed
# too, in case an interrupted spawn left one behind.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[teardown] $*"; }

removed=0
for ctn in "$WEB_CTN" "$DB_CTN" "$ATTACKER_CTN" "$SW_CTN" "$HELPER_CTN"; do
    if docker ps -a --format '{{.Names}}' | grep -qx "$ctn"; then
        log "removing $ctn"
        docker rm -f "$ctn" >/dev/null 2>&1 && removed=$(( removed + 1 ))
    fi
done

if [ "$removed" -eq 0 ]; then
    log "nothing to remove; the lab was not running"
else
    log "removed $removed container(s). The lab is gone."
fi
