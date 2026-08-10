#!/bin/bash
# Router starter config. It forwards between the attacker's subnet (ext,
# 104.0.0.0/24) and the network under survey (int, 104.1.0.0/24), and that is all
# it does.
#
# There is deliberately no filtering here. This lab is reconnaissance only: the
# learner measures what a scan of someone else's network reveals, and a router
# that dropped or rate-limited probes would measure the filter instead. Detecting
# and blocking a scan is the subject of a later lab, not this one.
#
# The router answers on 104.1.0.1, so it is one of the addresses a sweep of the
# /24 finds. That is intentional: a live address is not necessarily a host with
# services, and the router is the first example of the difference.
set -e

ip address add 104.0.0.1/24 dev ext 2>/dev/null || true
ip address add 104.1.0.1/24 dev int 2>/dev/null || true
ip link set ext up
ip link set int up

# Forwarding is switched on when the container is created (spawn.sh passes
# --sysctl net.ipv4.ip_forward=1), not here. Docker mounts /proc/sys read-only in
# an unprivileged container, so writing it at runtime would need the router to be
# privileged, and nothing else in this lab does. No ACL and no filtering follow
# it: every probe the attacker sends crosses to the target network, and every
# reply crosses back.
# What this prints is streamed into the TUI's Spawn panel, so it names no
# address, port, service or account: the learner reads this before they have
# scanned anything, and all of that is what Parts 1 to 3 have them find.
echo "router up: forwarding between 104.0.0.0/24 and the target range"
