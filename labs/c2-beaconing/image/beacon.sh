#!/bin/sh
# The implant, on whichever workstation the lab put it on.
#
# It does one thing: send a fixed-length request to a controller at intervals,
# read the reply, and wait. There is no exploit, no persistence and no lateral
# movement in this lab, because none of those is what the exercise is about. The
# whole of what makes this findable, and the whole of what the learner is graded
# on finding, is the SHAPE of the flow it produces: how often, to where, how big,
# and in which direction the bytes go.
#
# The three stages are read from the stage file between check-ins, so advancing
# the incident is a matter of writing a digit rather than restarting anything:
#
#   1  HTTP POST to the controller's plain port, at exactly $INTERVAL seconds
#   2  the same request over TLS on 443, with the wait drawn afresh each time
#      between $JITTER_MIN and $JITTER_MAX
#   3  the same as stage 2, to an address that has not appeared before
#
# Every address, port, path and interval comes from $1, the configuration file
# written by default_config on the one machine that runs this. Nothing is
# hardcoded here: this script is baked into the image every container in the lab
# shares, and a learner reading it on the gateway is meant to learn nothing from
# it.
set -u

CONF="${1:-/etc/minilabs/beacon.conf}"
[ -f "$CONF" ] || { echo "beacon: no configuration at $CONF" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"

: "${STAGE_FILE:?}" "${BODY_FILE:?}" "${INTERVAL:?}" "${JITTER_MIN:?}" "${JITTER_MAX:?}"
: "${STAGE1_URL:?}" "${STAGE2_URL:?}" "${STAGE3_URL:?}" "${FIRST_DELAY:?}"

# A uniform draw from the kernel's own entropy. `awk -v seed=...` was the
# alternative and is worse here: seeding it from the clock makes two workstations
# started in the same second draw the same sequence.
rand_between() {   # <min> <max>
    lo="$1"; hi="$2"
    span=$(( hi - lo + 1 ))
    n="$( od -An -N2 -tu2 < /dev/urandom | tr -dc '0-9' )"
    [ -n "$n" ] || n=0
    echo $(( lo + n % span ))
}

url_for() {
    case "$1" in
        1) echo "$STAGE1_URL" ;;
        2) echo "$STAGE2_URL" ;;
        3) echo "$STAGE3_URL" ;;
        *) echo "$STAGE1_URL" ;;
    esac
}

wait_for() {
    case "$1" in
        1) echo "$INTERVAL" ;;
        *) rand_between "$JITTER_MIN" "$JITTER_MAX" ;;
    esac
}

# -k because the controller's certificate is self-signed and nothing has been
# told to trust it. --max-time matters more than it looks: once the learner's
# egress policy is in place the connection gets no answer at all, and without a
# bound this would sit in one connect attempt for the kernel's whole retry
# schedule and stop checking the stage file.
send() {   # <url>
    curl -s -k -o /dev/null -m 10 \
        -H 'Content-Type: application/octet-stream' \
        --data-binary "@${BODY_FILE}" \
        "$1" 2>/dev/null || true
}

stage_now() { tr -dc '0-9' < "$STAGE_FILE" 2>/dev/null || echo 1; }

prev=""
countdown="$FIRST_DELAY"

# One-second ticks rather than one long sleep. The countdown is what sets the
# interval; the tick is what lets a stage change take effect within a couple of
# seconds instead of at the end of a wait that may be 42 seconds long.
while :; do
    stage="$( stage_now )"
    [ -n "$stage" ] || stage=1
    if [ "$stage" != "$prev" ]; then
        prev="$stage"
        countdown=2
    fi

    if [ "$countdown" -le 0 ]; then
        send "$( url_for "$stage" )"
        countdown="$( wait_for "$stage" )"
    fi

    sleep 1
    countdown=$(( countdown - 1 ))
done
