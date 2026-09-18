#!/usr/bin/env bash
# What the editor is doing, and the URL if there is one.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

need_docker

# The URL is printed only after confirming the container is actually running.
# A state file left behind by a crashed daemon otherwise sends the user to a dead
# port, which reads as a broken editor rather than as a stopped one.
if ! editor_running; then
    if [ -f "$STATE_FILE" ]; then
        log "the editor is NOT running."
        log "a state file from an earlier run is still here; its URL is dead."
        log "start it again with the Start editor action."
    else
        log "the editor is not running. Start it with the Start editor action."
    fi
    exit 0
fi

PORT="$( state_field port )"
URL="$( state_field url )"
TIER="$( state_field tier )"

log "the editor is running."
echo
echo "  URL       $URL"
echo "  port      127.0.0.1:$PORT"
case "$TIER" in
    B) echo "  tier      B: it can reach the Docker daemon, which is root-equivalent on this machine" ;;
    *) echo "  tier      A: no access to Docker" ;;
esac
echo
echo "  On another machine:"
echo "    ssh -L ${PORT}:127.0.0.1:${PORT} $( id -un )@$( hostname )"
echo
echo "  sandboxes $SANDBOX_ROOT"
if [ -d "$SANDBOX_ROOT" ]; then
    n=0
    for d in "$SANDBOX_ROOT"/*/; do
        [ -f "$d/topology.toml" ] || continue
        n=$(( n + 1 ))
    done
    echo "            $n project(s)"
fi
