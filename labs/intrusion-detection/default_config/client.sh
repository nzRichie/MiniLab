#!/bin/sh
# Starter configuration for the internal workstation.
#
# It does nothing on its own. Every packet it sends is one the learner asks it
# to send, which is what keeps the server's rule counters readable: a counter
# that moves did so because of something the learner just did.
set -e

ip addr flush dev 124-lan 2>/dev/null || true
ip addr add 124.0.0.20/24 dev 124-lan
ip link set 124-lan up
ip route replace default via 124.0.0.1

echo "[client] 124.0.0.20/24 via 124.0.0.1"
