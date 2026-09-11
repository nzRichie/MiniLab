#!/bin/sh
# Starter config for ws2: a second, uncompromised workstation.
#
# It exists as the legitimate-DNS baseline: an ordinary inside host that only
# ever resolves ordinary names through the resolver. Status resolves
# www.example.lab from here, so "ordinary resolution still works" is checked from
# a machine that has nothing to do with the channel, rather than from the one
# the file left from.
#
# It is idempotent: reset.sh re-runs it.
set -eu

PREFIXLEN=24
WS2_IP="119.0.0.34"
GW_INSIDE_IP="119.0.0.1"
RESOLVER_IP="119.0.0.2"
LAN_IF="119-lan"

ip addr replace "${WS2_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up
ip route replace default via "$GW_INSIDE_IP"

printf 'nameserver %s\n' "$RESOLVER_IP" > /etc/resolv.conf

echo "ws2: addressed ${WS2_IP}, resolver ${RESOLVER_IP}, clean host"
