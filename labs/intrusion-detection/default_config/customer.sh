#!/bin/sh
# Starter configuration for the outside reader of the public web site.
#
# The site is meant to be reachable from anywhere, so this machine is the
# measurement that says a rule aimed at the telnet service stayed aimed at the
# telnet service. It is on the same segment and the same prefix as the attacker,
# which is what makes a rule written against that whole prefix cost something.
set -e

ip addr flush dev 124-ext 2>/dev/null || true
ip addr add 124.1.0.77/24 dev 124-ext
ip link set 124-ext up
ip route replace default via 124.1.0.1

echo "[customer] 124.1.0.77/24 via 124.1.0.1"
