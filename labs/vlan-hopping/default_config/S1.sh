#!/bin/bash
# S1 (access switch) starter config - the vulnerable baseline the defender fixes.
# Runs inside the switch container; spawn.sh has already created br0 and added the
# two ports below. Port names and VLAN ids are the fixed values pinned in
# scripts/lib.sh; they are hardcoded here because this script runs standalone.
#
# The attacker's port is the lax one. native-untagged with tag=10 and trunks=10
# means it accepts the attacker's ordinary untagged VLAN 10 traffic AND a frame
# already tagged with VLAN 10 (the outer tag of a double-tagged frame). It trunks
# ONLY VLAN 10, so a single VLAN 20 tag is dropped: the learner has to double-tag.
#
# The trunk to S2 carries VLAN 10 and VLAN 20, with native VLAN 10. Native VLAN 10
# equals the attacker's access VLAN, which is the whole bug: VLAN 10 egresses this
# trunk UNTAGGED, stripping the outer tag and letting the inner VLAN 20 through.
set -e

ovs-vsctl set port 103-attacker vlan_mode=native-untagged tag=10 trunks=10
ovs-vsctl set port 103-S2        vlan_mode=native-untagged tag=10 trunks=10,20

echo "S1 baseline: 103-attacker native-untagged (native 10, trunks 10); trunk 103-S2 native 10, trunks 10,20"
