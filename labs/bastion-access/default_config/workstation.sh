#!/bin/sh
# Starter config for the operator's workstation: the machine outside the site,
# and the vantage every sweep in this lab is run from.
#
# It holds no key any machine in the site trusts, because the operator has not
# made any yet. What it has is reachability, and narrowing that is the whole lab.
set -eu

PREFIXLEN=24
WS_IP="114.0.0.10"
EDGE_EXT_IP="114.0.0.1"

ip addr replace "${WS_IP}/${PREFIXLEN}" dev 114-ext
ip link set 114-ext up
ip route replace default via "$EDGE_EXT_IP"

# Everything the learner puts in ~/.ssh is removed, so a reset returns the
# workstation to an operator who has generated nothing: no key pairs, no client
# configuration, and no record of a host key that a rebuilt container no longer
# has. The directory itself is recreated with the mode ssh insists on, because
# `docker exec` runs with umask 0022 under a rootful daemon and 0000 under a
# rootless one, and ssh refuses to use a private key in a world-readable
# directory.
rm -rf /root/.ssh
mkdir -p /root/.ssh
chmod 700 /root/.ssh

echo "workstation: addressed; no keys, no client configuration"
