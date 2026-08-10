#!/bin/bash
# Starter config for S1, the access switch the victim and the attacker plug into.
#
# The one setting that matters is the size of the MAC learning table. 16 is small
# on purpose: a real access switch holds 8,000 to 128,000 addresses, which a flood
# still fills but only after minutes and megabytes, while 16 fills in milliseconds
# and makes every measurement in this lab repeatable on a laptop. ovs-vswitchd
# refuses to go below 10, so 16 is close to the smallest table this lab could use.
#
# Nothing else is set. In particular no access port limits which source addresses
# it will accept, and no address is pinned to a port, which is the gap the learner
# closes in Part 2.
ovs-vsctl set bridge br0 other_config:mac-table-size=16
echo "S1: MAC table limited to $(ovs-vsctl get bridge br0 other_config:mac-table-size) entries, no port security"
