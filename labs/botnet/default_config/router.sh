#!/bin/sh
# Starter config for the router: address the three legs, and forward. No
# filtering at all, because Part 4's whole point is that the learner writes it.
#
# ip_forward is already 1 (set at `docker run`, because /proc/sys is read-only
# in the container). This script only addresses the interfaces and flushes any
# rules a previous run's learner left behind, so a reset returns the router to
# an open forwarder.
set -eu

R_INSIDE_IP="128.0.0.1"
R_FIELD_IP="128.1.0.1"
R_OP_IP="128.2.0.1"
PREFIXLEN=24
IF_INSIDE="128-S1"
IF_FIELD="128-S2"
IF_OP="128-S3"

ip addr replace "${R_INSIDE_IP}/${PREFIXLEN}" dev "$IF_INSIDE"
ip addr replace "${R_FIELD_IP}/${PREFIXLEN}"  dev "$IF_FIELD"
ip addr replace "${R_OP_IP}/${PREFIXLEN}"     dev "$IF_OP"
ip link set "$IF_INSIDE" up
ip link set "$IF_FIELD" up
ip link set "$IF_OP" up

# Every leg is directly connected, so the router needs no routes beyond the
# three the addresses give it. It reaches all three subnets already.

# Return the forward path to open. A learner's iptables rules, whichever move
# they reached, live in the FORWARD chain of the filter table; flushing it and
# setting the policy back to ACCEPT is what makes reset.sh return the router to
# baseline. The nat and mangle tables are never touched by this lab.
iptables -F FORWARD 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true

echo "router: three legs addressed, forwarding on, FORWARD chain open"
