#!/bin/sh
# Starter config for host2: an ordinary field machine running sshd.
#
# Six machines share the field segment (128.1.0.0/24). This one is reached the
# way every field host is: sshd on tcp/22 accepting a root password login. The
# addresses across the segment are scattered rather than consecutive, so a
# learner who finds one host cannot guess the next.
#
# THE PASSWORD LAYOUT IS THE LAB'S FIRST LESSON, arrived at from the attacker's
# side. Four of the six hosts share one weak root password; two hold a different
# one that is on no wordlist. Which is which is not printed anywhere the learner
# is pointed at. See default_config/host4.sh, whose loot file records it, and
# scripts/lib.sh, which is the single source of truth.
set -eu

HOST_IP="128.1.0.13"
PREFIXLEN=24
FIELD_IF="128-S2"
FIELD_GW="128.1.0.1"
ROOT_PW="Harbour-2019"

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_PID="/run/sshd.pid"

# --- addressing -----------------------------------------------------------
ip addr replace "${HOST_IP}/${PREFIXLEN}" dev "$FIELD_IF"
ip link set "$FIELD_IF" up
# One default route via the router reaches the inside and operator legs both.
ip route replace default via "$FIELD_GW"

# --- sshd, accepting a root password login --------------------------------
#
# The base image ships a hardened sshd_config (PasswordAuthentication no,
# PermitRootLogin prohibit-password), because the course network is reached with
# keys. This lab needs the opposite: a root password login is exactly what the
# recruiter uses. A pristine copy is taken on the first run and restored on
# every run after, so a learner's or a task's edits are replaced rather than
# patched, and a reset returns the host to the state Part 1 assumes.
[ -f "${SSHD_CONFIG}.lab-orig" ] || cp "$SSHD_CONFIG" "${SSHD_CONFIG}.lab-orig"
cp "${SSHD_CONFIG}.lab-orig" "$SSHD_CONFIG"

# sshd uses the FIRST value it obtains for a keyword, so a line the shipped file
# already sets is rewritten in place; one it left commented is appended.
sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' "$SSHD_CONFIG"
grep -q '^PasswordAuthentication yes' "$SSHD_CONFIG" || echo 'PasswordAuthentication yes' >> "$SSHD_CONFIG"
echo 'PermitRootLogin yes' >> "$SSHD_CONFIG"

echo "root:${ROOT_PW}" | chpasswd

# Host keys are generated once and kept: a reset that regenerated them would
# make the recruiter's next login fail on a host-key mismatch, which has nothing
# to do with anything the lab teaches. StrictHostKeyChecking=no on the client
# side covers it either way.
ssh-keygen -A >/dev/null 2>&1 || true

# Restart sshd cleanly. Kill by pidfile, wait for the port to free, then start.
# `pkill -x sshd` is a fallback for a daemon started before the pidfile existed;
# it is not the primary path, because OpenSSH rewrites its argv and an exact
# name match can miss the listener.
if [ -f "$SSHD_PID" ]; then kill "$( cat "$SSHD_PID" )" 2>/dev/null || true; fi
pkill -x sshd 2>/dev/null || true
i=0
while [ "$i" -lt 50 ]; do
    netstat -tln 2>/dev/null | grep -q ':22 ' || break
    i=$(( i + 1 )); sleep 0.1
done
/usr/sbin/sshd
echo "host2: addressed 128.1.0.13, sshd up, root password set"
