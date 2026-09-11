#!/usr/bin/env bash
# Remove this lab's containers and nothing else.
#
# It must never call the platform's own cleanup.sh or hard_reset.sh, which wipe
# the entire mini-internet. There is no host network state to clean: every veth
# in this lab lives inside a container's namespace, so removing the containers
# removes them. The helper is removed too, in case an interrupted spawn left one
# behind.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[teardown] $*"; }

for role in workstation scanner client holdout S1 netadmin_helper; do
    ctn="$( ctn_of "$role" )"
    if docker ps -a --format '{{.Names}}' | grep -qx "$ctn"; then
        log "removing $ctn"
        docker rm -f "$ctn" >/dev/null 2>&1 || true
    fi
done

log "done. The images are left in place; remove them with:"
log "  docker rmi $HOST_IMAGE $HOLDOUT_IMAGE"
