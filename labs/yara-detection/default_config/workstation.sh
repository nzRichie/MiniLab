#!/bin/sh
# Starter config for workstation: the analysis box, and the machine every rule
# in this lab is written on.
#
# It arrives addressed, with the corpus mounted read-only in the image and no
# rule file at all. /root/rules.yar is what the learner creates and what
# status.sh scores; nothing here writes it, because the rule is the whole of
# what the lab grades.
#
# It is idempotent: reset.sh re-runs it, which is what removes a rule file and
# any scratch copy of a sample a previous attempt left behind.
set -eu

PREFIXLEN=24
WORKSTATION_IP="126.0.0.10"
LAN_IF="126-lan"

RULES_FILE="/root/rules.yar"
WORKDIR="/root/work"

ip addr replace "${WORKSTATION_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# The learner's own scratch directory: somewhere to unpack a copy of a sample
# with `upx -d` without writing into the read-only corpus. Every mode is set
# explicitly rather than left to the ambient umask, which docker exec sets to
# 0022 under a rootful daemon and 0000 under a rootless one.
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
chmod 755 "$WORKDIR"

# A rule file left over from an earlier attempt would be scored as if it were
# this one's, so it goes.
rm -f "$RULES_FILE"

echo "workstation: addressed ${WORKSTATION_IP}, corpus at /srv/corpus, no rule file yet"
echo "workstation: $(ls /srv/corpus/set-a/*.exe /srv/corpus/set-b/*.exe 2>/dev/null | wc -l) samples"
