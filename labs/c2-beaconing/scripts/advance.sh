#!/usr/bin/env bash
# Advance the incident to its next stage.
#
# The lab's seventh action, which most labs do not have. It exists because this
# lab's subject is not a fixed end state but a sequence: the learner writes a
# rule against what they measured, and then the thing they measured changes and
# the rule has to answer for itself. Something has to move the incident on, and
# it is not the learner's own configuration.
#
# What it prints is deliberately thin. It says which stage the incident is at
# and nothing about what changed, because working that out from a fresh capture
# is the exercise. The handout says the same thing: capture again.
#
#   stage 1 -> 2   the implant's behaviour changes
#   stage 2 -> 3   the controller moves
#
# The stage is a digit in a file the implant re-reads between check-ins, so
# nothing here restarts the implant and its process has been running since
# spawn either way.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[advance] $*"; }

running "$INFECTED_CTN" || {
    echo "The lab is not running. Spawn it first." >&2
    exit 1
}

current="$( beacon_stage )"
case "${current:-}" in
    ''|*[!0-9]*) current=1 ;;
esac

if [ $# -ge 1 ]; then
    # An explicit stage. selftest.sh uses this to walk the stages in order
    # without depending on where a previous run left the lab.
    want="$1"
    case "$want" in
        [1-9]*) ;;
        *) echo "usage: $( basename "$0" ) [stage]   (1 to $BEACON_MAX_STAGE)" >&2; exit 2 ;;
    esac
else
    want=$(( current + 1 ))
fi

if [ "$want" -gt "$BEACON_MAX_STAGE" ]; then
    echo "The incident is already at its last stage (${BEACON_MAX_STAGE} of ${BEACON_MAX_STAGE})."
    echo "Reset the lab to start it again from stage 1."
    exit 0
fi

# Stage 3 is the controller moving to an address that has appeared in no capture
# the learner has taken. The address is added to the outside host here rather
# than at spawn, because an address that exists from the start is an address a
# learner can find before the stage that introduces it.
if [ "$want" -ge 3 ]; then
    docker exec "$EXT2_CTN" ip addr replace "${C2_MOVED_IP}/${PREFIXLEN}" dev "$EXT_IF" >/dev/null
fi

docker exec "$INFECTED_CTN" sh -c "echo $want > $BEACON_STAGE_FILE"

log "the incident is now at stage ${want} of ${BEACON_MAX_STAGE}."
log "the implant reads the stage between check-ins, so the change takes effect"
log "within a few seconds. Nothing was restarted and nothing was told to you"
log "about what changed: take a fresh capture on the gateway and read it."
