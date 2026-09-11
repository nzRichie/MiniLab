#!/bin/sh
# Starter configuration for the operator's workstation.
#
# It does nothing but hold an address. Its job in the lab is to send the one
# legitimate request that every hardening stage is measured against, so that a
# build which stops the exploit by stopping the service fails the oracle rather
# than passing it.
set -e

IF="121-lan"
ADDR="121.0.0.20/24"

ip addr flush dev "$IF" 2>/dev/null || true
ip addr add "$ADDR" dev "$IF"
ip link set dev "$IF" up

echo "ops: $ADDR on $IF"
