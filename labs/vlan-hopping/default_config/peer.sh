#!/bin/bash
# Benign peer starter config. A plain VLAN 10 host on S2 at 103.10.0.11, doing
# nothing wrong. It is the attacker's honest reach: same VLAN, different switch, so
# the attacker legitimately talks to it across the trunk. That legitimate path is
# the control for the lab: any defence that stops the VLAN hop must leave this
# working. Nothing to configure but the address.
set -e

ip address add 103.10.0.11/24 dev 103-S2 2>/dev/null || true
ip link set 103-S2 up
echo "peer up at 103.10.0.11 on VLAN 10"
