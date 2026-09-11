#!/bin/sh
# Starter config for ops: the operator's workstation on the appliance's segment.
#
# It is the legitimate caller of the network-tools page and the vantage every
# liveness check is run from. Its requests never cross the gateway to reach the
# appliance -- both machines sit on the inside segment -- so a liveness check run
# here tests the appliance and the reachability check the page performs, and not
# the path between the two segments.
#
# It is idempotent: reset.sh re-runs it.
set -eu

PREFIXLEN=24
OPS_IP="120.0.0.20"
GW_INSIDE_IP="120.0.0.1"
LAN_IF="120-lan"

ip addr replace "${OPS_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up
ip route replace default via "$GW_INSIDE_IP"

echo "ops: addressed ${OPS_IP}, default route via ${GW_INSIDE_IP}"
