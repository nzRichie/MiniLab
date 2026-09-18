#!/usr/bin/env bash
# Stop the editor and clear its state.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

need_docker

if docker container inspect "$EDITOR_CTN" >/dev/null 2>&1; then
    docker rm -f "$EDITOR_CTN" >/dev/null 2>&1 || true
    log "the editor is stopped."
else
    log "the editor was not running."
fi

# The state file goes with it. Leaving it behind is what makes a later status
# print a URL for a port nothing is listening on.
rm -f "$STATE_FILE" "$STATE_FILE.lock"

# The token goes too. It is useless once the container it authenticated is gone,
# a restart mints a fresh one, and a secret left on disk for no reason is worse
# than one that is not there. Any browser tab still open on the old URL stops
# working either way, because the new token is different.
rm -f "$TOKEN_FILE"

log "your sandboxes under $SANDBOX_ROOT are untouched."
