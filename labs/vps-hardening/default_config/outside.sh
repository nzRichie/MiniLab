#!/bin/sh
# Starter config for the outside host: the vantage every port sweep in this lab
# is run from. It holds no credential the server trusts and it is not meant to;
# what it has is reachability, which is the thing the server has to survive.
set -eu

PREFIXLEN=24
OUTSIDE_IP="110.0.0.10"
ROUTER_EXT_IP="110.0.0.1"

ip addr replace "${OUTSIDE_IP}/${PREFIXLEN}" dev 110-ext
ip link set 110-ext up
ip route replace default via "$ROUTER_EXT_IP"

echo "outside: addressed; sweep vantage ready"
