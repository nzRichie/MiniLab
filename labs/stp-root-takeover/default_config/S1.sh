#!/bin/bash
# Starter config for S1, the intended root bridge.
#
# S1 gets the lowest configured priority of the three, so a correctly working
# network roots its spanning tree here and the blocked port lands on the S2-S3
# link. Nothing else is set: in particular no access port carries any protection
# against a forged BPDU, which is the gap the learner closes in Part 2.
ovs-vsctl set bridge br0 stp_enable=true other_config:stp-priority=4096
echo "S1: STP enabled, bridge priority 4096 (intended root)"
