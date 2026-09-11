#!/bin/sh
# Starter config for the administrative client: the machine the learner works
# from once the server stops accepting passwords, and the one source SSH is
# meant to be reachable from when the lab is finished.
#
# It arrives with an address and nothing else. In particular it holds NO key
# pair: generating one and installing its public half on the server is the
# learner's work in Part 2, so this script removes the whole of /root/.ssh rather
# than creating any of it. That also throws away known_hosts, which is what stops
# a key from an earlier spawn making a later login fail for the wrong reason.
set -eu

PREFIXLEN=24
ADMIN_IP="110.2.0.30"
ROUTER_MGMT_IP="110.2.0.1"

ip addr replace "${ADMIN_IP}/${PREFIXLEN}" dev 110-mgmt
ip link set 110-mgmt up
ip route replace default via "$ROUTER_MGMT_IP"

# Any tunnel left open by an earlier run of the lab, closed. `pkill -x ssh`
# matches the process name exactly; a pattern match on the command line would
# also match this script, whose own text contains the string.
pkill -x ssh 2>/dev/null || true

rm -rf /root/.ssh

echo "admin: addressed; no key pair yet, which is Part 2's work"
