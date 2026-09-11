#!/bin/sh
# Starter config for attacker: the machine every request in this lab is sent
# from, and the machine the direct login at the end of Part 1 is attempted from.
#
# It arrives with an address on the segment and the two tools the lab needs,
# both of which are in the image: curl, for the requests, and the mariadb
# client, for the login. It is pre-armed with nothing else. Every payload in
# this lab is typed by the learner; there is no script here that sends one.
set -eu

PREFIXLEN=24
ATTACKER_IP="122.0.0.66"
LAN_IF="122-lan"

ip addr replace "${ATTACKER_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# Nothing accumulates on this host across a run except whatever the learner
# saved, which is left alone: a reset returns the database to its starter state,
# and notes taken during Part 1 are not lab state.

echo "attacker: addressed ${ATTACKER_IP}, curl and the mariadb client are installed"
