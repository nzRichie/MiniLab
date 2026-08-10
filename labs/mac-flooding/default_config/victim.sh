#!/bin/bash
# Starter config for the victim: the lab segment's file server, on an access port
# of S1. The ten staff machines behind the uplink use it, and it sends its own
# traffic out through the gateway. That second path, victim to gateway, is the one
# the attacker wants to read.
ip addr flush dev 106-S1 2>/dev/null
ip addr add 106.0.0.20/24 dev 106-S1
ip link set 106-S1 up
ip route replace default via 106.0.0.1 dev 106-S1 2>/dev/null
echo "victim: 106.0.0.20/24 on 106-S1 (MAC $(cat /sys/class/net/106-S1/address))"
