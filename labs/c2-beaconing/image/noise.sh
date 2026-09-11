#!/bin/sh
# The traffic that is supposed to be there, on every workstation.
#
# Two loops run at once, and the difference between them is what makes Part 2 an
# exercise rather than a lookup:
#
#   browsing  a request every $BROWSE_MIN to $BROWSE_MAX seconds to a page drawn
#             from $BROWSE_URLS. Uneven gaps, several destinations, replies of
#             different sizes.
#   polling   a request to $POLL_URL every $POLL_INTERVAL seconds, starting
#             $POLL_OFFSET seconds in. Perfectly regular, and every workstation
#             in the lab runs one, which is what stops "repeats on a fixed
#             period" from picking out the implant on its own.
#
# The offset is per workstation so the polls do not all arrive in the same
# second; three flows landing together read as one event in a capture.
#
# Every address, path and interval comes from $1, the configuration file written
# by default_config on each machine. Nothing is hardcoded here, because this
# script is baked into the image every container shares.
set -u

CONF="${1:-/etc/minilabs/noise.conf}"
[ -f "$CONF" ] || { echo "noise: no configuration at $CONF" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"

: "${BROWSE_URLS:?}" "${BROWSE_MIN:?}" "${BROWSE_MAX:?}"
: "${POLL_URL:?}" "${POLL_INTERVAL:?}" "${POLL_OFFSET:?}"

rand_between() {   # <min> <max>
    lo="$1"; hi="$2"
    span=$(( hi - lo + 1 ))
    n="$( od -An -N2 -tu2 < /dev/urandom | tr -dc '0-9' )"
    [ -n "$n" ] || n=0
    echo $(( lo + n % span ))
}

# One of $BROWSE_URLS, drawn uniformly. `set --` turns the space-separated list
# into positional parameters, which is the only indexable list a POSIX shell has.
pick_url() {
    # shellcheck disable=SC2086
    set -- $BROWSE_URLS
    i="$( rand_between 1 $# )"
    eval "echo \${$i}"
}

fetch() {   # <url>
    curl -s -o /dev/null -m 6 "$1" 2>/dev/null || true
}

browse_loop() {
    while :; do
        sleep "$( rand_between "$BROWSE_MIN" "$BROWSE_MAX" )"
        fetch "$( pick_url )"
    done
}

poll_loop() {
    sleep "$POLL_OFFSET"
    while :; do
        fetch "$POLL_URL"
        sleep "$POLL_INTERVAL"
    done
}

browse_loop &
poll_loop &
wait
