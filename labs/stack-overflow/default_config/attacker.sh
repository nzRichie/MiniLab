#!/bin/sh
# Starter configuration for the attacker's machine.
#
# It arrives with an address and the stock tools the image ships: python3 to
# write the payload's raw bytes and nc to send them. It is given no addresses,
# no offset and no payload, so working the attack still means measuring both
# numbers on the appliance and building the request by hand.
set -e

IF="121-lan"
ADDR="121.0.0.66/24"

ip addr flush dev "$IF" 2>/dev/null || true
ip addr add "$ADDR" dev "$IF"
ip link set dev "$IF" up

echo "attacker: $ADDR on $IF"
