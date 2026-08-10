#!/bin/bash
# Starter config for S3: the switch the gateway and the attacker's second link
# attach to.
#
# Priority 12288 puts it last in the election. Its port 105-attacker is the other
# lax access port: in Part 2 the attacker claims the root out of both of its NICs
# at once, so this switch has to be protected too.
ovs-vsctl set bridge br0 stp_enable=true other_config:stp-priority=12288
echo "S3: STP enabled, bridge priority 12288"
