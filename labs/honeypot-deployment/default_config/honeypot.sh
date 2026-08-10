#!/bin/sh
# Starter config for the honeypot container: addressed, routed, and nothing else.
#
# Cowrie is installed in the image but is deliberately left unconfigured and not
# running. Writing etc/cowrie.cfg and etc/userdb.txt and starting the daemon is
# the learner's Part 2 work, and a container that arrived with a working decoy
# would hand over the graded half of the lab.
set -eu

PREFIXLEN=24
HONEY_IP="106.2.0.10"
ROUTER_HONEY_IP="106.2.0.1"

ip addr replace "${HONEY_IP}/${PREFIXLEN}" dev 106-honey
ip link set 106-honey up
ip route replace default via "$ROUTER_HONEY_IP"

# Cowrie writes its logs, its PID file and its captured artifacts under this
# tree and refuses to start if it cannot. The image creates it; this only
# re-asserts ownership, because a bind mount or a rebuild could leave it owned
# by root and the failure that produces is a permission error deep in a Twisted
# traceback rather than anything a learner could act on.
chown -R cowrie:cowrie /opt/cowrie

echo "honeypot: addressed; Cowrie is installed at /opt/cowrie and is NOT running"
