#!/bin/sh
# Starter configuration for the router.
#
# It forwards between the inside and the outside segment and translates nothing,
# so every packet that reaches the server still carries the address of the
# machine that sent it. That is what makes a source-address match on the server
# mean anything, and it is why this script writes no nat table.
#
# The outside interface carries an address on each of the two outside prefixes.
# They share one segment: the attacker's machine holds an address in each of
# them too, and a rule written against one of them does nothing about the other.
# That is Part 1's fourth step, and it needs no second link to arrange.
set -e

ip addr flush dev lan  2>/dev/null || true
ip addr flush dev ext  2>/dev/null || true

ip addr add 124.0.0.1/24 dev lan
ip link set lan up

ip addr add 124.1.0.1/24 dev ext
ip addr add 124.9.0.1/24 dev ext
ip link set ext up

# ip_forward is set at `docker run` rather than here: Docker mounts /proc/sys
# read-only in an unprivileged container.
echo "[router] lan 124.0.0.1/24, ext 124.1.0.1/24 and 124.9.0.1/24, forwarding, no nat"
