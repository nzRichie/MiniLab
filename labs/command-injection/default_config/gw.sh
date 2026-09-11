#!/bin/sh
# Starter config for gw: the gateway between the appliance's segment and the
# outside, and the machine Part 2C is worked from.
#
# It arrives with two addressed interfaces, forwarding on, and NO filtering at
# all. That is the starting position the lab argues against: a network that
# controls what may come in (nothing here does, because the appliance's page is
# meant to be public) and controls nothing about what the appliance itself may
# open a connection to. Part 2C is where the learner writes the allowlist.
#
# net.ipv4.ip_forward is set at container creation rather than here, because
# Docker mounts /proc/sys read-only in an unprivileged container.
#
# There is no address translation, and that is a decision rather than an
# omission. Without NAT every packet the appliance originates still carries
# 120.0.0.10 when the gateway sees it, which is what lets Part 2C's allowlist be
# written against that one source rather than against a shared address.
#
# It is idempotent, and reset.sh re-runs it to throw away whatever the learner
# wrote in Part 2C.
set -eu

PREFIXLEN=24
GW_INSIDE_IP="120.0.0.1"
GW_OUTSIDE_IP="120.1.0.1"
GW_INSIDE_IF="lan"
GW_OUTSIDE_IF="ext"

NFT_TABLE="egress"

ip addr replace "${GW_INSIDE_IP}/${PREFIXLEN}" dev "$GW_INSIDE_IF"
ip addr replace "${GW_OUTSIDE_IP}/${PREFIXLEN}" dev "$GW_OUTSIDE_IF"
ip link set "$GW_INSIDE_IF" up
ip link set "$GW_OUTSIDE_IF" up

# Remove the table Part 2C creates, so a reset returns the gateway to forwarding
# everything in both directions.
nft delete table inet "$NFT_TABLE" 2>/dev/null || true

echo "gw: addressed ${GW_INSIDE_IP} inside and ${GW_OUTSIDE_IP} outside, forwarding, no filtering"
