#!/bin/bash
# Starter configuration for inside-1, a client on the private segment.
#
# One address out of the private prefix and one default route through the edge
# router. Nothing else: a client behind a NAT is not configured for it and does
# not know it is behind one, which is the property the whole arrangement is built
# to have.
set -e

ip addr flush dev 112-S1 2>/dev/null || true
ip addr add 192.168.10.11/24 dev 112-S1
ip link set dev 112-S1 up
ip route replace default via 192.168.10.1
