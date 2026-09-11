#!/usr/bin/env bash
# Return the lab to the state it spawned in WITHOUT tearing it down: the CA tree
# emptied of every key and certificate the learner created, the server serving
# its own self-signed certificate again, and the client's trust store back to the
# public authorities Alpine ships.
#
# This is the undo button for a learner who has issued four certificates, edited
# lighttpd's configuration three times and can no longer say which file the
# server is presenting. Every one of those undos lives in the three starter
# configs, so this script is nothing but "run them again".
#
# The one thing it does NOT throw away is the SSH key pair the server and the
# client reach the CA with. default_config/ca.sh regenerates it only when it is
# missing, because the other two containers hold a copy this script cannot
# replace, and a fresh key on the CA alone would lock both of them out with an
# error the learner has no way to interpret.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping the web service before its certificate is replaced"
docker exec "$SERVER_CTN" pkill -x lighttpd 2>/dev/null || true

echo "[reset] re-applying starter configs (this deletes every certificate you issued)"
for h in "${HOSTS[@]}"; do
    docker exec "$( ctn_of "$h" )" "/home/${h}.sh" >/dev/null 2>&1 || true
done

echo "[reset] the CA is empty, the server signs for itself again, and the client"
echo "[reset] trusts nothing that vouches for it."
