#!/bin/bash
# Victim starter config. A plain host on the core subnet, doing nothing wrong. It
# is the reflection target: the attacker forges 102.1.0.20 as the source of its
# queries, so every reflector's reply lands here. The victim never sent those
# queries; it only receives the flood. Nothing to configure — the defence is the
# router's job, not the victim's.
set -e

ip address add 102.1.0.20/24 dev 102-S1 2>/dev/null || true
ip link set 102-S1 up
ip route add default via 102.1.0.1 2>/dev/null || true
echo "victim up at 102.1.0.20"
