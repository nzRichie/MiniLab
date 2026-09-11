#!/bin/sh
# Starter config for attacker: the outside machine the learner works Part 1 from.
#
# It arrives with an address, a route, and nothing else. There is no attack tool
# here and nothing pre-armed: every request in Part 1 is a curl the learner
# types, and the listener is a netcat they start. What makes this machine the
# attacker is only where it sits, on the far side of the gateway from the
# appliance, which is the position Part 2C's allowlist is written against.
#
# It clears whatever a previous listener wrote, so a reset starts the record of
# what reached the attacker empty. pkill -x matches the process NAME exactly
# rather than the whole argv, so it cannot match this script; PID 1 in this
# container is `sleep infinity` and nothing here may match it.
#
# It is idempotent: reset.sh re-runs it.
set -eu

PREFIXLEN=24
ATTACKER_IP="120.1.0.66"
GW_OUTSIDE_IP="120.1.0.1"
EXT_IF="120-ext"

ip addr replace "${ATTACKER_IP}/${PREFIXLEN}" dev "$EXT_IF"
ip link set "$EXT_IF" up
ip route replace default via "$GW_OUTSIDE_IP"

pkill -x nc 2>/dev/null || true
pkill -x tail 2>/dev/null || true
rm -f /root/loot.txt /root/loot.err

echo "attacker: addressed ${ATTACKER_IP}, default route via ${GW_OUTSIDE_IP}, no listener running"
