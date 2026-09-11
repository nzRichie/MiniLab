#!/bin/sh
# Starter config for ws3: the third workstation, and the infected one.
#
# INSTRUCTOR NOTE. Which machine this is is an answer to the exercise. It is set
# up exactly like ws1 and ws2 -- same address scheme, same browsing, same
# thirty-second poll of the monitoring endpoint -- and then runs one more thing.
# That is the point: nothing about this machine's ordinary traffic marks it out,
# and the only difference visible from the gateway is one extra flow.
#
# The implant itself is /usr/local/lib/minilabs/beacon.sh, which is in the image
# every container shares and holds no addresses. What makes it a controller
# rather than a web fetch is entirely in the configuration file written below.
#
# It is idempotent, and the stage is written back to 1 every time, so a reset
# rewinds the incident as well as the machine.
set -eu

PREFIXLEN=24
WS_IP="118.0.0.43"
GW_INSIDE_IP="118.0.0.1"
WS_IF="118-lan"

NOISE_CONF="/etc/minilabs/noise.conf"
POLL_OFFSET=25

BEACON_CONF="/etc/minilabs/beacon.conf"
BEACON_STAGE_FILE="/etc/minilabs/beacon.stage"
BEACON_BODY="/etc/minilabs/beacon.body"
BEACON_BODY_BYTES=96

ip addr replace "${WS_IP}/${PREFIXLEN}" dev "$WS_IF"
ip link set "$WS_IF" up
ip route replace default via "$GW_INSIDE_IP"

mkdir -p /etc/minilabs
chmod 755 /etc/minilabs

# ---------------------------------------------------------------------------
# The ordinary traffic, identical to the other two workstations.
cat > "$NOISE_CONF" <<EOF
BROWSE_URLS="http://118.1.0.10/index.html http://118.1.0.10/notes.html http://118.1.0.10/guide.html http://118.1.0.10/changelog.html http://118.1.0.30/index.html http://118.1.0.30/guide.html"
BROWSE_MIN=3
BROWSE_MAX=17
POLL_URL="http://118.1.0.20/health"
POLL_INTERVAL=30
POLL_OFFSET=${POLL_OFFSET}
EOF

# ---------------------------------------------------------------------------
# The implant's configuration: the three destinations it uses as the incident
# advances, and the timing of each stage.
#
# Stage 1 is a plain HTTP POST to tcp/8080 every thirty seconds with no
# variation. Stage 2 is the same request over TLS on 443 with the wait drawn
# afresh between 18 and 42 seconds. Stage 3 changes only the address.
cat > "$BEACON_CONF" <<EOF
STAGE1_URL="http://118.1.0.66:8080/api/v1/status"
STAGE2_URL="https://118.1.0.66/api/v1/status"
STAGE3_URL="https://118.1.0.99/api/v1/status"
INTERVAL=30
JITTER_MIN=18
JITTER_MAX=42
FIRST_DELAY=7
BODY_FILE=${BEACON_BODY}
STAGE_FILE=${BEACON_STAGE_FILE}
EOF

# The request body: the same 96 bytes on every check-in, so the request length
# never varies. It is generated once and kept, rather than drawn fresh on each
# run, so that a learner who measures it in Part 2 and again in Part 4 gets the
# same number.
#
# `head -c` rather than `cut -c`: cut terminates its output with a newline, so
# the body would be 97 bytes and every Content-Length in the lab would be one
# more than the number the handout and the answer key state.
if [ ! -s "$BEACON_BODY" ]; then
    head -c 72 /dev/urandom | base64 | tr -d "\n" | head -c ${BEACON_BODY_BYTES} > "$BEACON_BODY"
fi

# Back to stage 1. A reset rewinds the incident, so a learner who advanced to
# stage 3 and then reset does not find the implant still talking to an address
# the handout has not introduced yet.
echo 1 > "$BEACON_STAGE_FILE"
chmod 644 "$BEACON_CONF" "$BEACON_STAGE_FILE" "$BEACON_BODY"

# ---------------------------------------------------------------------------
# Start both. The bracket in each pattern keeps `pkill -f` from matching the
# shell that runs it, whose own argv contains the string being searched for.
pkill -f '[n]oise\.sh' 2>/dev/null || true
pkill -f '[b]eacon\.sh' 2>/dev/null || true

setsid /usr/local/lib/minilabs/noise.sh "$NOISE_CONF" >/dev/null 2>&1 &
setsid /usr/local/lib/minilabs/beacon.sh "$BEACON_CONF" >/dev/null 2>&1 &

echo "ws3: addressed ${WS_IP}, browsing and polling; the implant is running at stage 1"
