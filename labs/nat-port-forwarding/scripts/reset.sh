#!/usr/bin/env bash
# Return the lab to the state it spawned in WITHOUT tearing it down: no nat table
# on the router, both web services running with empty access logs, and every
# address and route back where spawn put it.
#
# This is the undo button for a learner who has three chains, six rules and a
# ruleset that no longer matches anything they meant. All of the undoing lives in
# the five starter configs, so this script is mostly "run them again".
#
# The one thing beyond that is the connection-tracking table. A translation is
# decided once, on the first packet of a connection, and every later packet
# follows the entry rather than the ruleset; an entry that outlived the rule that
# created it makes the next fetch behave like a ruleset that is no longer loaded.
# default_config/router.sh flushes it for that reason, and this is the path that
# matters most, because a reset is exactly when a learner is about to retry
# something they just watched fail.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping both web services"
for h in webserver outside; do
    docker exec "$( ctn_of "$h" )" pkill -x lighttpd 2>/dev/null || true
done

echo "[reset] re-applying starter configs (this deletes every rule you wrote)"
for d in "${DEVICES[@]}"; do
    docker exec "$( ctn_of "$d" )" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] the router forwards between both segments and translates nothing."
