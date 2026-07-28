#!/bin/bash
# Attacker starter config — pre-armed (proposal: the attacker side uses `Config`).
# The image already carries arp-poison (scapy) + tcpdump, and IP forwarding is
# enabled at container-creation time (spawn.sh --sysctl), so here we just address
# the NIC.
ip address add 100.0.0.10/24 dev 100-S1
ip route add default via 100.0.0.1 2>/dev/null || true
