#!/bin/bash
# Attacker starter config - pre-armed (the attacker side boots ready). It sits on
# the customer edge at 102.0.0.10 with the router as its default gateway. The
# image already carries the kit: nping (forges a source address with -S), scapy
# and the baked `reflect` tool (craft the reflected DNS/NTP queries), and tcpdump.
# No attack runs at spawn; the handout starts each stage by hand.
set -e

ip address add 102.0.0.10/24 dev 102-cust 2>/dev/null || true
ip link set 102-cust up
ip route add default via 102.0.0.1 2>/dev/null || true
echo "attacker armed at 102.0.0.10 (nping -S, scapy, reflect available)"
