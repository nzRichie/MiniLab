#!/bin/sh
# The admin workstation's web probe.
#
# The site's own admin fetches the served page every few seconds. It is the
# fast half of the collateral-damage check: a defence that breaks the web
# service shows up here within seconds, well before the slow SSH probe would
# notice. It writes one line per run to its state file, which status.sh reads
# rather than running a fresh probe, so the line says whether the network
# worked for the admin while the learner was typing.
#
# Every parameter comes from the environment set by default_config/admin.sh, so
# this script names no address of its own.
set -u

: "${SERVER_URL:?}"
: "${WEB_INTERVAL:?}"
: "${WEB_STATE:?}"

mkdir -p "$( dirname "$WEB_STATE" )"

while :; do
    now="$( date +%s )"
    code="$( curl -s -o /dev/null -m 4 -w '%{http_code}' "$SERVER_URL" 2>/dev/null )"
    case "$code" in
        200) echo "$now ok $code"   > "$WEB_STATE" ;;
        *)   echo "$now fail ${code:-000}" > "$WEB_STATE" ;;
    esac
    sleep "$WEB_INTERVAL"
done
