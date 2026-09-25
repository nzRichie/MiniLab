#!/bin/sh
# Starter config for host3: one of the four flood sources.
#
# An ordinary machine on the field segment, reachable from the console the way
# the other three are: sshd on tcp/22 accepting a root password login. The
# console logs in, starts one bounded run of `flood`, and the run ends on its
# own when its count is spent.
#
# NOTHING ATTACK-SPECIFIC IS SET UP HERE. In particular the OUTPUT chain is
# flushed rather than pre-loaded: dropping this machine's own outbound RSTs is
# what Stage 2 needs to work at all, and finding that out is the first thing
# Stage 2 asks the learner to do. A rule that arrived pre-armed would answer
# question 7 before it was asked.
set -eu

HOST_IP="129.1.0.68"
PREFIXLEN=24
FIELD_IF="129-S2"
GW="129.1.0.1"
ROOT_PW="Riverbed-2021"

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_PID="/run/sshd.pid"

# --- addressing -----------------------------------------------------------
ip addr replace "${HOST_IP}/${PREFIXLEN}" dev "$FIELD_IF"
ip link set "$FIELD_IF" up
ip route replace default via "$GW"

# --- stop anything a previous run left behind -----------------------------
# Matched on the full path of the tool, never on `python3`, so nothing else
# written in python is caught by it.
pkill -f /usr/local/bin/flood 2>/dev/null || true
iptables -F OUTPUT 2>/dev/null || true

# --- sshd, accepting a root password login --------------------------------
#
# The base image ships a hardened sshd_config, because the course network is
# reached with keys. This lab needs a password login: it is how the console
# drives the four sources. A pristine copy is taken on the first run and
# restored on every run after, so edits are replaced rather than patched.
[ -f "${SSHD_CONFIG}.lab-orig" ] || cp "$SSHD_CONFIG" "${SSHD_CONFIG}.lab-orig"
cp "${SSHD_CONFIG}.lab-orig" "$SSHD_CONFIG"

# sshd uses the FIRST value it obtains for a keyword, so a line the shipped file
# already sets is rewritten in place; one it left commented is appended.
sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' "$SSHD_CONFIG"
grep -q '^PasswordAuthentication yes' "$SSHD_CONFIG" || echo 'PasswordAuthentication yes' >> "$SSHD_CONFIG"
echo 'PermitRootLogin yes' >> "$SSHD_CONFIG"

echo "root:${ROOT_PW}" | chpasswd
ssh-keygen -A >/dev/null 2>&1 || true

if [ -f "$SSHD_PID" ]; then kill "$( cat "$SSHD_PID" )" 2>/dev/null || true; fi
pkill -x sshd 2>/dev/null || true
i=0
while [ "$i" -lt 50 ]; do
    netstat -tln 2>/dev/null | grep -q ':22 ' || break
    i=$(( i + 1 )); sleep 0.1
done
/usr/sbin/sshd

echo "host3: addressed ${HOST_IP}, sshd up, no flood running, OUTPUT chain empty"
