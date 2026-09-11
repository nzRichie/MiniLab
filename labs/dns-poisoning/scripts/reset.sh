#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline WITHOUT tearing it down: stop
# any flood still running, throw away the resolver's cache along with whatever it
# was poisoned with, drop the learner's defences by re-applying the starter
# configs, and re-publish the zone's key. A learner who broke the resolver, or who
# wants to run Part 1 again from an empty cache, is back at the start.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping anything the attacker still has running"
docker exec "$ATTACKER_CTN" pkill -f dns-spoof 2>/dev/null || true
for d in "${DEVICES[@]}"; do
    docker exec "$(ctn_of "$d")" pkill -x tcpdump 2>/dev/null || true
done

echo "[reset] re-applying starter configs"
# Each starter config rewrites its device's named.conf and restarts named, so
# this undoes every edit the learner made to the resolver's settings and empties
# its cache at the same time. The order is lib.sh's: servers before the resolver
# that queries them.
for d in "${DEVICES[@]}"; do
    docker exec "$(ctn_of "$d")" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] re-publishing ${TARGET_ZONE}'s key signing key to the resolver"
# The authoritative server generated a fresh key when its starter config ran, so
# the copy the resolver holds has to be replaced or a learner reaching Part 2c
# would install a key that signs nothing.
anchor=""
for _ in $(seq 1 60); do
    anchor="$( docker exec "$AUTH_CTN" dig +short +timeout=2 +tries=1 \
        @127.0.0.1 -p 5353 "$TARGET_ZONE" DNSKEY 2>/dev/null \
        | awk '$1 == "257" { $1=$1; print; exit }' )"
    [ -n "$anchor" ] && break
    sleep 1
done
if [ -n "$anchor" ]; then
    key="$( echo "$anchor" | cut -d' ' -f4- | tr -d ' ' )"
    alg="$( echo "$anchor" | cut -d' ' -f3 )"
    docker exec -i "$RESOLVER_CTN" sh -c "cat > $TRUST_ANCHOR" <<EOF
// The public half of uni.lab's key signing key, as its operator published it.
// A resolver that installs this can check every signature in the zone against
// it. Nothing installs it automatically: see /etc/bind/trust-anchors.conf.
trust-anchors {
    "${TARGET_ZONE}." static-key 257 3 ${alg} "${key}";
};
EOF
else
    echo "[reset] warning: the authoritative server produced no key signing key" >&2
fi

echo "[reset] baseline restored: cache empty, defences off, ${TARGET_NAME} unpoisoned"
