#!/bin/bash
# Starter config for the attacker.
#
# Addressed on link A (into S2) only. Link B (into S3) is wired but held DOWN, so
# the lab starts with a single-homed attacker and Part 1 is an honest test of what
# winning the root election alone achieves. Raising link B and bridging the two
# NICs is Part 2, and it is the learner's own doing, not something spawn arranged.
#
# No bridge, no capture and no BPDU sender is started here: the attack is typed by
# hand.
ip addr flush dev 105-S2 2>/dev/null
ip addr add 105.0.0.10/24 dev 105-S2
ip link set 105-S2 up
ip link set 105-S3 down
echo "attacker: 105.0.0.10/24 on 105-S2; second NIC 105-S3 is DOWN"
