#!/usr/bin/env bash
# Return the lab to the state it spawned in WITHOUT tearing it down: every
# address gone, every lab-facing interface down, every route the learner added
# removed, every ARP cache and every cached route exception thrown away.
#
# This is the undo button for a learner who has typed enough half-right commands
# that they no longer know what their own network holds. It is also how the
# handout's last section is repeated: the ICMP redirect that section is about
# only happens on a path the kernel has no cached exception for.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping any capture still running"
for d in "${DEVICES[@]}"; do
    docker exec "$( ctn_of "$d" )" pkill -x tcpdump 2>/dev/null || true
done

echo "[reset] re-applying starter configs (this deletes everything you configured)"
# Each starter config flushes its device's routes, addresses and neighbour
# entries and puts the interface back down. Flushing the routes is also what
# discards a cached route exception an ICMP redirect installed, because the
# exception hangs off the route it modifies.
for d in "${DEVICES[@]}"; do
    docker exec "$( ctn_of "$d" )" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] the network is wired and unconfigured, exactly as spawn.sh left it"
