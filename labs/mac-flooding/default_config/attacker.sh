#!/bin/bash
# Starter config for the attacker: an ordinary host on an ordinary access port of
# S1, with one address and one MAC, exactly like the victim next to it.
#
# No flood is started here and no capture is running. The attack is typed by hand.
ip addr flush dev 106-S1 2>/dev/null
ip addr add 106.0.0.10/24 dev 106-S1
ip link set 106-S1 up
ip route replace default via 106.0.0.1 dev 106-S1 2>/dev/null
echo "attacker: 106.0.0.10/24 on 106-S1 (MAC $(cat /sys/class/net/106-S1/address))"
