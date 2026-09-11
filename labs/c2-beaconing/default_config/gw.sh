#!/bin/sh
# Starter config for gw: the gateway, and the machine the whole lab is worked
# from.
#
# It arrives with two addressed interfaces, forwarding on, and NO filtering of
# any kind. That is the state Part 1 starts in and the state a reset returns to:
# every packet the workstations send to the outside crosses this machine and
# none of them is examined, which is what makes the first capture an honest
# picture of what the network is doing.
#
# net.ipv4.ip_forward is set at container creation rather than here, because
# Docker mounts /proc/sys read-only in an unprivileged container.
#
# There is no address translation on this gateway, and that is a decision rather
# than an omission. With NAT, every packet leaving here would carry the
# gateway's own address and a capture would say only that "something inside"
# talks to the controller. Without it, the workstation's own address is in every
# packet, and identifying the infected machine is a matter of reading a column.
#
# It is idempotent, and reset.sh re-runs it to throw away the learner's policy.
set -eu

PREFIXLEN=24
GW_INSIDE_IP="118.0.0.1"
GW_OUTSIDE_IP="118.1.0.1"
GW_INSIDE_IF="lan"
GW_OUTSIDE_IF="ext"

NFT_TABLE="egress"

ip addr replace "${GW_INSIDE_IP}/${PREFIXLEN}" dev "$GW_INSIDE_IF"
ip addr replace "${GW_OUTSIDE_IP}/${PREFIXLEN}" dev "$GW_OUTSIDE_IF"
ip link set "$GW_INSIDE_IF" up
ip link set "$GW_OUTSIDE_IF" up

# The learner's whole answer lives in this table, so a reset removes it. Leaving
# it behind would start the next run with traffic already blocked and no line in
# the handout to explain why the first capture is empty.
nft delete table inet "$NFT_TABLE" 2>/dev/null || true

# Any capture file left in place by a previous run. They are up to a few
# megabytes each and a learner who worked through the lab twice would otherwise
# be reading yesterday's traffic.
rm -f /tmp/egress.pcap /tmp/measure.pcap

echo "gw: addressed ${GW_INSIDE_IP} inside and ${GW_OUTSIDE_IP} outside, forwarding, no filtering"
