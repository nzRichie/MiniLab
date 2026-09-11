#!/bin/sh
# Starter config for mon: the upstream monitor on the outside segment.
#
# It is the address the appliance's own reachability checks are aimed at, and it
# is on the far side of the gateway on purpose. A liveness check that pinged
# something on the appliance's own segment would pass whatever Part 2C's
# allowlist said, because no such packet ever reaches the gateway; pinging mon
# crosses it, so the check really does measure whether the allowlist left the
# appliance's legitimate traffic alone.
#
# It runs no service. Replying to an echo request is the whole of its job.
#
# It is idempotent: reset.sh re-runs it.
set -eu

PREFIXLEN=24
MON_IP="120.1.0.20"
GW_OUTSIDE_IP="120.1.0.1"
EXT_IF="120-ext"

ip addr replace "${MON_IP}/${PREFIXLEN}" dev "$EXT_IF"
ip link set "$EXT_IF" up
ip route replace default via "$GW_OUTSIDE_IP"

echo "mon: addressed ${MON_IP}, default route via ${GW_OUTSIDE_IP}"
