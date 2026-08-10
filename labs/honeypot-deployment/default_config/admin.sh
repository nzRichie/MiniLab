#!/bin/sh
# Starter config for the management station. It exists so the defence has
# something to break: every stage of this lab is paired with a check that the
# admin can still reach the production host, and a learner who stops the attacker
# by making production unreachable fails that check rather than passing the lab.
set -eu

PREFIXLEN=24
ADMIN_IP="106.3.0.30"
ROUTER_MGMT_IP="106.3.0.1"

ip addr replace "${ADMIN_IP}/${PREFIXLEN}" dev 106-mgmt
ip link set 106-mgmt up
ip route replace default via "$ROUTER_MGMT_IP"

echo "admin: addressed; management station ready"
