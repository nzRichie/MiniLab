#!/bin/bash
# Starter config for the gateway: the segment's way off site, behind S2 and so
# behind S1's uplink. It is the destination the victim's frames are addressed to,
# which is why losing its entry from S1's table is what makes those frames leak.
ip addr flush dev 106-S2 2>/dev/null
ip addr add 106.0.0.1/24 dev 106-S2
ip link set 106-S2 up
# Forwarding is turned on by a --sysctl flag on `docker run` in spawn.sh, not
# here: /proc/sys is read-only in a container that is not --privileged.
echo "gateway: 106.0.0.1/24 on 106-S2 (MAC $(cat /sys/class/net/106-S2/address)), forwarding=$(cat /proc/sys/net/ipv4/ip_forward)"
