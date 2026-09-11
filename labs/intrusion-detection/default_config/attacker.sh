#!/bin/sh
# Starter configuration for the outside machine the lab is attacked from.
#
# It holds an address on each of the two outside prefixes. Both are real
# addresses of this machine on one segment, so a probe sent from either gets its
# replies back the ordinary way and the learner reads success or failure off
# nping's own output rather than off the server. A rule that names one of the
# two prefixes is a rule this machine walks around by naming the other.
set -e

ip addr flush dev 124-ext 2>/dev/null || true
ip addr add 124.1.0.66/24 dev 124-ext
ip addr add 124.9.0.66/24 dev 124-ext
ip link set 124-ext up
ip route replace default via 124.1.0.1

echo "[attacker] 124.1.0.66/24 and 124.9.0.66/24 via 124.1.0.1"
