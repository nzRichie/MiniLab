#!/bin/sh
# Starter config for the admin workstation: the site's own staff machine.
#
# It sits on the field segment among the six ordinary hosts, but it runs no
# sshd, so nothing the botnet does ever recruits it. Its two jobs are the lab's
# collateral-damage check, and both of them cross the router, which is what
# makes them something a policy at the router can break:
#
#   web probe   fetches the inside server's page every 5 seconds. The fast
#               check: a defence that breaks the web service shows here within
#               seconds.
#   ssh probe   logs into the inside server as the maintenance account every 60
#               seconds. The reason tcp/22 toward the server cannot be switched
#               off, and the login a per-source rate cap must stay clear of.
#
# Each probe writes one line to a state file that status.sh reads, so Status
# reports whether the network worked for the admin while the learner was typing,
# without shelling in.
set -eu

ADMIN_IP="128.1.0.77"
PREFIXLEN=24
FIELD_IF="128-S2"
FIELD_GW="128.1.0.1"

SERVER_IP="128.0.0.20"
SYSOPS_USER="sysops"
SYSOPS_PW="Foxglove-Tarn-6182"

# --- addressing -----------------------------------------------------------
ip addr replace "${ADMIN_IP}/${PREFIXLEN}" dev "$FIELD_IF"
ip link set "$FIELD_IF" up
ip route replace default via "$FIELD_GW"

# --- restart the two probe loops ------------------------------------------
# A reset re-runs this file, so any probe left running from a previous session
# is stopped by its pidfile before a fresh one starts. They are killed by
# pidfile, and the fallback matches the full script path, never the interpreter
# name, so nothing else on the machine is caught.
mkdir -p /run/minilabs /var/lib/minilabs

WEB_PID="/run/minilabs/probe-web.pid"
SSH_PID="/run/minilabs/probe-ssh.pid"

for pf in "$WEB_PID" "$SSH_PID"; do
    if [ -f "$pf" ]; then kill "$( cat "$pf" )" 2>/dev/null || true; fi
done
pkill -f '/usr/local/lib/minilabs/probe-web.sh' 2>/dev/null || true
pkill -f '/usr/local/lib/minilabs/probe-ssh.sh' 2>/dev/null || true

SERVER_URL="http://${SERVER_IP}/index.html" \
WEB_INTERVAL=5 \
WEB_STATE="/var/lib/minilabs/admin-web.state" \
    setsid /usr/local/lib/minilabs/probe-web.sh >/dev/null 2>&1 &
echo $! > "$WEB_PID"

SERVER_ADDR="$SERVER_IP" \
SSH_USER="$SYSOPS_USER" \
SSH_PASS="$SYSOPS_PW" \
SSH_INTERVAL=60 \
SSH_STATE="/var/lib/minilabs/admin-ssh.state" \
    setsid /usr/local/lib/minilabs/probe-ssh.sh >/dev/null 2>&1 &
echo $! > "$SSH_PID"

echo "admin: ${ADMIN_IP} up; web probe every 5s, ssh probe every 60s"
