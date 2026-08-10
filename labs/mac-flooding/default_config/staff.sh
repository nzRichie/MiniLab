#!/bin/bash
# Starter config for the staff machines: ten interfaces behind S2, 106.0.0.31 to
# 106.0.0.40, each on its own port of S2 with its own MAC address.
#
# They are here for one reason. S1 learns every one of these ten addresses on the
# single port facing S2, so that uplink carries eleven addresses (ten staff plus
# the gateway) where an access port carries one. Open vSwitch evicts from the port
# holding the most entries, so the uplink is the only port on S1 with more than
# its share to lose, and it is the only thing a flood on an access port can reach.
#
# They also have to keep talking, and faster than the gateway does. An entry is
# refreshed each time its address sends a frame, and the eviction picks the least
# recently refreshed entry on the port. Each staff machine pings the file server
# ten times a second; the gateway's address is only refreshed when it answers the
# server, twice a second at most. So within a tenth of a second of any gateway
# reply, all ten staff addresses are more recent than the gateway's and the
# gateway is the entry the next eviction takes. That is what makes the attack land
# on the gateway every time instead of on a random one of the eleven.

# The ARP rules that keep these ten addresses looking like ten separate hosts
# (arp_ignore=1, arp_announce=2) are NOT set here. Docker mounts /proc/sys
# read-only in a container that is not --privileged, so `sysctl -w` in this file
# would fail with "Read-only file system" and quietly leave the defaults in place.
# They are passed as --sysctl flags on `docker run` in spawn.sh instead.

# Stop any keepalives from a previous run before restarting them, so re-applying
# this config (which reset.sh does) does not leave two sets running.
pkill -f 'ping -I 106-S2-' >/dev/null 2>&1
sleep 0.2

up=0
for n in $(seq 1 10); do
    ifname=$(printf '106-S2-%02d' "$n")
    addr="106.0.0.$((30 + n))"
    ip addr flush dev "$ifname" 2>/dev/null
    ip addr add "$addr/24" dev "$ifname" 2>/dev/null
    ip link set "$ifname" up 2>/dev/null
    # The keepalive. -I binds to the device, so the frame leaves with that
    # interface's own MAC address and S1 learns it on the uplink.
    nohup ping -I "$ifname" -i 0.1 -W 1 106.0.0.20 >/dev/null 2>&1 &
    up=$((up + 1))
done

echo "staff: $up machines up, 106.0.0.31-106.0.0.$((30 + up)), each polling the file server 10x/s"
