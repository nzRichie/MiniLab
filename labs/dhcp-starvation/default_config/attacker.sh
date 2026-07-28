#!/bin/bash
# Attacker starter config — pre-armed (proposal: the attacker side uses `Config`).
# The image already carries dhcp-starve (the pool flooder) and a second copy of
# ISC dhcpd for the rogue server. Here we only take a static address for the
# attacker's own identity, 101.0.0.66 — the address it will later hand victims as
# their default gateway. No attack runs at spawn: the handout starts each stage.
set -e

ip address add 101.0.0.66/24 dev 101-S1 2>/dev/null || true
ip link set 101-S1 up
# A route toward the real server so the attacker can relay traffic it intercepts
# once it is a victim's gateway (a transparent on-path position).
ip route add default via 101.0.0.1 2>/dev/null || true
echo "attacker armed at 101.0.0.66 (dhcp-starve + rogue dhcpd available)"
