#!/bin/bash
# Starter config for S2: the switch the victim and the attacker's first link
# attach to.
#
# Priority 8192 puts it second in the election, behind S1. Its port 105-attacker
# is an ordinary access port with a host on the end, and it will honour any BPDU
# that host chooses to send. That is the vulnerability.
ovs-vsctl set bridge br0 stp_enable=true other_config:stp-priority=8192
echo "S2: STP enabled, bridge priority 8192"
