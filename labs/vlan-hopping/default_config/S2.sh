#!/bin/bash
# S2 starter config - holds the victim's VLAN. Runs inside the switch container;
# spawn.sh has already created br0 and added the three ports below. Port names and
# VLAN ids are the fixed values pinned in scripts/lib.sh.
#
# The host ports are proper strict access ports from the start: peer on VLAN 10,
# victim on VLAN 20. An access port drops any tagged ingress, so these two are not
# the weak point; the attacker's lax port on S1 is. The trunk to S1 mirrors S1's
# side: VLAN 10 and VLAN 20 carried, native VLAN 10 (the same vulnerable native).
set -e

ovs-vsctl set port 103-peer   vlan_mode=access tag=10
ovs-vsctl set port 103-victim vlan_mode=access tag=20
ovs-vsctl set port 103-S1     vlan_mode=native-untagged tag=10 trunks=10,20

echo "S2 baseline: 103-peer access 10; 103-victim access 20; trunk 103-S1 native 10, trunks 10,20"
