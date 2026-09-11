#!/usr/bin/env bash
# Return the lab to the state it spawned in WITHOUT tearing it down: the
# administrative account and its installed key gone, sshd_config and
# /etc/sudoers back to what the server was delivered with, the administrative
# endpoint bound to every address again, and the packet filter emptied.
#
# This is the undo button for a learner who has edited enough of sshd_config that
# they no longer know what the file holds. Every one of those undos lives in
# default_config/server.sh, so this script is nothing but "run the starter
# configs again".
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] closing any SSH tunnel the admin station still holds open"
docker exec "$ADMIN_CTN" pkill -x ssh 2>/dev/null || true

echo "[reset] re-applying starter configs (this deletes everything you configured)"
for d in "${DEVICES[@]}"; do
    docker exec "$( ctn_of "$d" )" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] the server is delivered again: root by password, three ports, no filter"
