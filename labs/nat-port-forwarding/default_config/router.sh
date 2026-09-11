#!/bin/bash
# Starter configuration for the edge router.
#
# It gets both segments addressed and forwards between them, and that is all it
# does. Every translation rule in this lab is written by the learner; this script
# is also what reset.sh re-runs, so its other job is to throw that work away by
# leaving the nat table absent rather than empty.
#
# ip_forward is NOT set here. Docker mounts /proc/sys read-only in an
# unprivileged container, so it is set at `docker run` instead, and making the
# router privileged just to write one value is more privilege than this lab
# needs. The handout says so, so that a learner who tries `sysctl -w` and is
# refused knows why.
set -e

ip addr flush dev inside  2>/dev/null || true
ip addr flush dev outside 2>/dev/null || true

ip addr add 192.168.10.1/24 dev inside
ip addr add 112.0.0.1/24    dev outside
ip link set dev inside  up
ip link set dev outside up

# Both segments are directly connected, so the routing table needs nothing added:
# the two prefix routes the kernel installs alongside the two addresses are the
# whole of what this router knows. Nothing beyond them exists in the lab, so a
# default route would point at nothing.

# Delete the whole table rather than flushing its chains. A flushed nat table
# still holds two base chains registered at the prerouting and postrouting
# hooks, and the learner's first command in Part 2 is the one that creates the
# table; finding it already there would make that command fail.
nft delete table ip nat 2>/dev/null || true

# Connection tracking decides a packet's translation once, on the first packet of
# the connection, and every later packet of that connection follows the entry
# rather than the ruleset. An entry created while a rule was absent therefore
# outlives the rule's arrival, so a reset that left the table populated would
# leave the learner's next fetch behaving like the ruleset they just deleted.
conntrack -F >/dev/null 2>&1 || true
