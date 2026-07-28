#!/bin/bash
# Attacker starter config - pre-armed (the attacker side boots ready). It sits on
# an access port in VLAN 10 at 103.10.0.10. The image already carries the kit:
# scapy and the baked `vlan-double-tag` tool craft the double-tagged frame, and
# iproute2 adds an 802.1Q subinterface for the single-tag attempt. No attack runs
# at spawn; the handout starts each stage by hand. There is no default route: the
# lab is two VLANs with no router, and the point is the L2 hop, not L3 forwarding.
set -e

ip address add 103.10.0.10/24 dev 103-S1 2>/dev/null || true
ip link set 103-S1 up
echo "attacker armed at 103.10.0.10 on VLAN 10 (scapy, vlan-double-tag available)"
