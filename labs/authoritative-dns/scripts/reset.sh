#!/usr/bin/env bash
# Return the lab to its clean pre-configuration baseline, in place. No teardown:
# the containers, the wiring and the switch stay exactly as they are, and only
# what the learner wrote is undone.
#
# Every zone file the learner wrote lives under /var/bind, and every zone
# statement lives in /etc/bind/zones.conf. Neither is written by a starter
# config, so re-running a starter config restores the empty zones.conf and
# restarts named, but leaves the zone files behind. named holding no zone
# statement would ignore them, but a learner who then re-declares a zone would
# silently pick up their previous file rather than starting from nothing, so the
# files are removed here as well.
#
# The root server and the client are re-applied too, even though the learner
# never edits them: a learner who went looking and changed something on either
# has a lab whose measuring instrument is wrong, and that is worth undoing.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

docker ps --format '{{.Names}}' | grep -qx "$PRIMARY_CTN" || {
    echo "The lab is not running ($PRIMARY_CTN is not up). Spawn it first." >&2
    exit 1
}

# The zone files, first, so a starter config's named restart cannot load one.
# The transferred copy under /var/bind/secondary goes too: it is not the
# learner's writing, but it is the result of it, and a secondary that still held
# a copy would answer for a zone nothing had declared.
for d in "${LEARNER_DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "removing zone files on $ctn"
    docker exec "$ctn" sh -c 'rm -f /var/bind/*.zone /var/bind/*.db /var/bind/secondary/* 2>/dev/null; :'
    docker exec "$ctn" sh -c ": > $NAMED_LOG"
done

for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "re-applying default_config/${d}.sh on $ctn"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

# The resolver caches what it learned, including the fact that a name did not
# exist. A reset that left the cache in place would have the next run answering
# out of it for as long as the negative TTL the learner chose.
log "emptying the resolver's cache on $CLIENT_CTN"
docker exec "$CLIENT_CTN" rndc flush >/dev/null 2>&1 || true

log "baseline restored: the three servers below the root hold no zone again."
log "Check it with:  $LAB_DIR/scripts/status.sh"
