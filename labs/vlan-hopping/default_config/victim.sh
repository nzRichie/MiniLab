#!/bin/bash
# Victim starter config. A plain VLAN 20 host on S2 at 103.20.0.20, doing nothing
# wrong. It is the hop target: the attacker's double-tagged frame is delivered here
# even though the attacker sits in VLAN 10 with no route to VLAN 20. The victim
# only receives; it never sent anything and cannot reply back across the hop.
# Nothing to configure but the address; the defence is the switch's job, not the
# victim's.
set -e

ip address add 103.20.0.20/24 dev 103-S2 2>/dev/null || true
ip link set 103-S2 up
echo "victim up at 103.20.0.20 on VLAN 20"
