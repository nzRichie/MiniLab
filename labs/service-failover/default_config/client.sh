#!/bin/sh
# Starter config for the client: the only machine on the front segment, and the
# vantage every number in this lab is measured from.
#
# It runs no service. What it holds is one address, one default route, and curl.
set -eu

PREFIXLEN=24
CLIENT_IP="117.0.0.10"
PROXY_FRONT_IP="117.0.0.1"
CLIENT_IF="117-front"

ip addr replace "${CLIENT_IP}/${PREFIXLEN}" dev "$CLIENT_IF"
ip link set "$CLIENT_IF" up

# The default route points at the proxy, which does not forward. That is not a
# mistake: the route is what makes the failure legible. Without it a packet aimed
# at a backend would be refused by this machine's own stack with "Network is
# unreachable", which says nothing about the proxy; with it the packet leaves,
# reaches a machine that will not forward it, and is silently discarded, which is
# what a learner reads as a filtered port.
ip route replace default via "$PROXY_FRONT_IP"

echo "client: addressed ${CLIENT_IP}, default route via ${PROXY_FRONT_IP}"
