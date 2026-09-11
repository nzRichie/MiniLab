#!/bin/sh
# Starter config for ws2: one of the three workstations on the inside segment.
#
# All three are set up the same way and all three produce the same two kinds of
# traffic: pages fetched from the two outside sites at uneven intervals, and a
# poll of the monitoring endpoint every thirty seconds. The poll is the reason
# this file matters to the exercise. It repeats on exactly the period the
# implant checks in on, so a learner who looks for "a flow that repeats
# regularly" finds four flows, and has to use something other than regularity to
# choose between them.
#
# The offset staggers this machine's poll against the other two so the three
# polls do not arrive in the same second.
#
# It is idempotent: reset.sh re-runs it, and it stops the generator it started
# last time before starting a new one.
set -eu

PREFIXLEN=24
WS_IP="118.0.0.32"
GW_INSIDE_IP="118.0.0.1"
WS_IF="118-lan"

NOISE_CONF="/etc/minilabs/noise.conf"
POLL_OFFSET=17

ip addr replace "${WS_IP}/${PREFIXLEN}" dev "$WS_IF"
ip link set "$WS_IF" up
ip route replace default via "$GW_INSIDE_IP"

mkdir -p /etc/minilabs
chmod 755 /etc/minilabs

# Every address the generator uses is written here rather than living in the
# generator, which is baked into the image all six containers share. A learner
# reading /usr/local/lib/minilabs/noise.sh on the gateway finds no addresses in
# it.
cat > "$NOISE_CONF" <<EOF
BROWSE_URLS="http://118.1.0.10/index.html http://118.1.0.10/notes.html http://118.1.0.10/guide.html http://118.1.0.10/changelog.html http://118.1.0.30/index.html http://118.1.0.30/guide.html"
BROWSE_MIN=3
BROWSE_MAX=17
POLL_URL="http://118.1.0.20/health"
POLL_INTERVAL=30
POLL_OFFSET=${POLL_OFFSET}
EOF

# The bracket in the pattern is load-bearing. `pkill -f noise.sh` run from
# `sh -c` matches the shell running it too, because that string is in the
# shell's own argv, so the command kills its own parent and sometimes leaves the
# generator running. `[n]oise` matches the running process and not the pattern.
pkill -f '[n]oise\.sh' 2>/dev/null || true

# setsid so the generator outlives the `docker exec` that started it: without a
# session of its own it is a child of the exec's shell and goes away with it.
setsid /usr/local/lib/minilabs/noise.sh "$NOISE_CONF" >/dev/null 2>&1 &

echo "ws2: addressed ${WS_IP}, browsing and polling the monitoring endpoint"
