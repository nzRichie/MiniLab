#!/bin/sh
# Starter config for holdout: the scoring appliance.
#
# It holds the ten files Part 3 is scored against and runs no service at all.
# status.sh copies the learner's rule file to /tmp/scoring.yar and runs yara
# here, which is the only thing this container ever does. It is addressed so
# that it appears in the topology the handout draws and so that a spawn that
# failed to wire it is visible, not because anything connects to it.
set -eu

PREFIXLEN=24
HOLDOUT_IP="126.0.0.40"
LAN_IF="126-lan"

ip addr replace "${HOLDOUT_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# A rule file staged by an earlier scoring run would be scored again if the
# learner's file had since been deleted, so it goes.
rm -f /tmp/scoring.yar

echo "holdout: addressed ${HOLDOUT_IP}, $(ls /srv/holdout/*.exe | wc -l) files, no service listening"
