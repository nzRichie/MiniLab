#!/bin/sh
# Starter config for mid-2. It configures nothing, and that is the point: this lab
# hands the learner a wired network with no addressing on it and has them build
# the addressing themselves. What this script does is assert that blank state, so
# that re-running it (which is all scripts/reset.sh does) throws away whatever the
# learner has configured and puts the host back where it started.
#
# Interface(s) on this host: 108-MID
set -e

for IF in 108-MID; do
    # Order matters. Routes go first, because a default route through a gateway on
    # this interface is a route whose output device this is, and flushing the
    # addresses would delete it out from under the flush. Then the addresses,
    # which takes the connected route with them. Then the neighbour entries, so
    # no stale ARP cache survives a reset. Then the link, back down, which is how
    # every lab-facing interface in this lab starts.
    ip route flush dev "$IF" 2>/dev/null || true
    ip addr flush dev "$IF" 2>/dev/null || true
    ip neigh flush dev "$IF" 2>/dev/null || true
    ip link set dev "$IF" down 2>/dev/null || true
done
