#!/bin/sh
# Starter config for the admin workstation: the measurement.
#
# It sits on the field segment, among the four flood sources and the two
# reflectors, and not on the inside leg beside the victim. That placement is the
# whole reason the lab can be measured at all: a qdisc shapes only what leaves
# the interface it is attached to, so an inside host talking to the victim never
# crosses the bottleneck. One measured 8 Mbit/s through a 1 Mbit/s shaper with
# the router's counters not moving by a single byte.
#
# It starts NO background job. Every measurement in this lab is one the learner
# runs, with `probe`, at a moment they chose; a probe loop running on a timer
# would put its own traffic through the bottleneck the learner is reading the
# drop counter of.
set -eu

ADMIN_IP="129.1.0.77"
PREFIXLEN=24
FIELD_IF="129-S2"
GW="129.1.0.1"
STATE="/var/lib/minilabs/probe.state"

ip addr replace "${ADMIN_IP}/${PREFIXLEN}" dev "$FIELD_IF"
ip link set "$FIELD_IF" up
ip route replace default via "$GW"

# The state file starts empty, so Status after a reset reports no reading rather
# than yesterday's.
mkdir -p /var/lib/minilabs
: > "$STATE"
chmod 755 /var/lib/minilabs
chmod 644 "$STATE"

echo "admin: ${ADMIN_IP} up. Measure with:  probe --target 129.0.0.20 --name www.lab all"
