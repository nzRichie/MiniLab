#!/bin/sh
# Starter config for the attacker: addressed, routed, and holding an SSH client.
#
# Nothing here is pre-armed, because this lab's attack is not an exploit. The
# attacker arrives with a working credential for the production host, which the
# handout hands over, and the whole of Part 1 is using it. What the lab is about
# begins after that.
set -eu

PREFIXLEN=24
ATTACKER_IP="106.0.0.10"
ROUTER_EXT_IP="106.0.0.1"

ip addr replace "${ATTACKER_IP}/${PREFIXLEN}" dev 106-ext
ip link set 106-ext up
ip route replace default via "$ROUTER_EXT_IP"

# The attacker reconnects to the same address repeatedly across the lab, and the
# host key it answers with changes when the learner puts a decoy behind that
# address. That change is the single most interesting thing the attacker could
# notice, and it is a handout question; what it must not do is stop the session
# with a host-key warning before the learner gets to see it. Recording keys in a
# throwaway file keeps the warning out of the way without hiding the fingerprint,
# which `ssh` still prints on every first connection to a given key.
mkdir -p /root/.ssh
cat > /root/.ssh/config <<'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
chmod 700 /root/.ssh
chmod 600 /root/.ssh/config

echo "attacker: addressed; ssh client ready"
