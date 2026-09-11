#!/bin/sh
# Starter config: the router between the campus, the authoritative server, and the
# attacker. It forwards between all three and filters nothing, so every query,
# every answer and every forged answer arrives. Its only job in this lab is to
# keep the attacker off the path between the resolver and the authoritative
# server, which is what makes the attack an off-path one.
#
# ip_forward is set at container creation instead of here: Docker mounts
# /proc/sys read-only in an unprivileged container, and making the router
# privileged just to write one sysctl is more privilege than this lab needs.
set -e

ip addr replace 107.1.0.1/24 dev campus
ip link set campus up

ip addr replace 107.2.0.1/24 dev auth
ip link set auth up

ip addr replace 107.3.0.1/24 dev hostile
ip link set hostile up

echo "router: campus 107.1.0.1/24, auth 107.2.0.1/24, hostile 107.3.0.1/24"
