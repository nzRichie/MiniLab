#!/bin/sh
# Starter config for the router: address all three segments, and nothing else.
#
# What this deliberately does NOT do is filter anything. The router in this lab
# is plumbing: it forwards between the external, server and management segments
# and has no opinion about what may reach what. That is the point. It means the
# outside host can put a packet in front of every port the server holds,
# including the SSH port on an address the lab calls "management", so nothing the
# learner writes on the server is enforced anywhere but on the server.
set -eu

PREFIXLEN=24

ROUTER_EXT_IP="110.0.0.1"
ROUTER_SRV_IP="110.1.0.1"
ROUTER_MGMT_IP="110.2.0.1"

# `addr replace` rather than `addr add`, so this script is safe to run a second
# time: reset.sh re-runs it to rebuild the baseline, and an `add` would fail with
# EEXIST on the first line and leave the rest of the file unexecuted.
ip addr replace "${ROUTER_EXT_IP}/${PREFIXLEN}"  dev ext
ip addr replace "${ROUTER_SRV_IP}/${PREFIXLEN}"  dev srv
ip addr replace "${ROUTER_MGMT_IP}/${PREFIXLEN}" dev mgmt

ip link set ext  up
ip link set srv  up
ip link set mgmt up

echo "router: three segments addressed, forwarding, filtering nothing"
