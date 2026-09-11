#!/bin/sh
# Starter config for the proxy: the machine the whole lab is written on.
#
# It arrives addressed on both segments and running nothing. /etc/haproxy/haproxy.cfg
# holds a global section and a defaults section and no frontend or backend at all.
# That file is VALID: `haproxy -c` accepts it and `haproxy -D` starts a daemon
# from it quite happily. What the daemon does not do is bind anything, because a
# listening socket comes from a frontend and there is no frontend. A learner who
# starts it before writing one gets a running process, no listener, and the same
# refused connection they had before, which is a more useful thing to have met
# than a config file that would not load.
#
# What is already written is only what the lab's own tooling depends on. The
# runtime API socket is here rather than left to the learner because the Status
# action reads the pool through it, and an oracle that starts working only after
# the learner has written the line it needs could not report on Part 1 at all.
set -eu

PREFIXLEN=24
PROXY_FRONT_IP="117.0.0.1"
PROXY_BACK_IP="117.1.0.1"
P_FRONT_IF="front"
P_BACK_IF="back"

HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
HAPROXY_PID="/run/haproxy.pid"

ip addr replace "${PROXY_FRONT_IP}/${PREFIXLEN}" dev "$P_FRONT_IF"
ip link set "$P_FRONT_IF" up
ip addr replace "${PROXY_BACK_IP}/${PREFIXLEN}" dev "$P_BACK_IF"
ip link set "$P_BACK_IF" up

# No default route. This machine is the boundary between the two segments and has
# a connected route to each, so it needs nothing else, and giving it a default
# route would be giving it a path off a lab that is supposed to have none.

# ---------------------------------------------------------------------------
# Stop anything a previous run left serving, so a reset starts from no daemon
# rather than from the learner's last reload.
if [ -f "$HAPROXY_PID" ]; then
    kill "$( cat "$HAPROXY_PID" )" 2>/dev/null || true
    sleep 0.3
fi
pkill -x haproxy 2>/dev/null || true
rm -f "$HAPROXY_PID"

mkdir -p /run/haproxy
chmod 755 /run/haproxy

# ---------------------------------------------------------------------------
# The starter configuration.
#
# timeout connect is present with a deliberately unhelpful value. Leaving it out
# would be defensible, but HAProxy then warns on every start that the backend has
# missing timeouts, and a warning that is expected for three parts and then
# resolved teaches a learner to read past warnings. A value that is present,
# plausible and five times the client's own patience is the more useful starting
# point: it costs nothing for the first three parts and is the direct cause of
# the failures that come back in Part 4.
cat > "$HAPROXY_CFG" <<'CFG'
# HAProxy configuration for the failover lab.
#
# Sections you write are added below. Check a change before loading it:
#
#     haproxy -c -f /etc/haproxy/haproxy.cfg
#
global
    # The runtime API. One line in, one document out: `show stat` reports the
    # pool, `set server` changes a server's state without a reload.
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s

defaults
    mode http

    # How long a connection may take to ESTABLISH to a backend. Part 4.
    timeout connect 5s

    # How long an idle client, and an accepted backend, may go without sending.
    timeout client 10s
    timeout server 10s

# ---------------------------------------------------------------------------
# Part 1: a frontend that binds the service address, and a backend holding the
#         two servers it balances over.
# Part 2: an active health check on each server.
# Part 3: a retry policy, so a request already in flight survives a backend
#         disappearing underneath it.
# Part 4: a connect timeout that fits inside the client's own patience.
CFG
chmod 644 "$HAPROXY_CFG"

echo "proxy: addressed ${PROXY_FRONT_IP} (front) and ${PROXY_BACK_IP} (back); haproxy not running, no frontend or backend configured"
