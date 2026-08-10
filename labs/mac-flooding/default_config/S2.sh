#!/bin/bash
# Starter config for S2, the distribution switch carrying the gateway and the ten
# staff machines.
#
# S2 keeps the stock table size, because the attack is aimed at S1 and there is no
# reason to shrink a switch the lab does not measure. Note what this does NOT buy
# it: the flood crosses the uplink, so S2 learns every forged address too and its
# table fills just as completely (2048 of 2048, measured). S2 does not leak anyway,
# and the reason is the port layout rather than the table size. Every address S2
# needs sits on a port of its own holding exactly one entry, and eviction takes
# from the port holding the most, which is always the uplink full of forged
# addresses. A switch is only hurt by a full table where some port is carrying
# more than its share, and on S2 none is.
ovs-vsctl set bridge br0 other_config:mac-table-size=2048
echo "S2: MAC table limited to $(ovs-vsctl get bridge br0 other_config:mac-table-size) entries (the stock value)"
