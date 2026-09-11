#!/usr/bin/env bash
# Return the lab to the state it spawned in WITHOUT tearing it down: no drop-in
# rules on any machine, no per-host files and no rotation policy on the
# collector, a local log file back on every machine, and every service running.
#
# This is the undo button for a learner whose collector is writing to the wrong
# path, and it is also the only way back once the incident has run: the incident
# deletes db's local log, and reset is what puts a file there again.
#
# All of the undoing lives in the four starter configs, so this script is mostly
# "run them again". The one thing beyond that is stopping the services first: a
# starter config restarts each of them, and a `pkill -x` that runs in the same
# breath as the restart is a race the restart sometimes loses.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping the services"
for h in "${DEVICES[@]}"; do
    docker exec "$( ctn_of "$h" )" sh -c \
        'pkill -x lighttpd 2>/dev/null; pkill -x sshd 2>/dev/null; pkill -x rsyslogd 2>/dev/null; true' \
        >/dev/null 2>&1 || true
done
sleep 1

echo "[reset] re-applying starter configs (this deletes every rule you wrote)"
for d in "${DEVICES[@]}"; do
    docker exec "$( ctn_of "$d" )" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] each machine logs to its own disk again; the collector receives nothing."
