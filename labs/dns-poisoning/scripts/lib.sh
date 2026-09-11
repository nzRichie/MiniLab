#!/usr/bin/env bash
# Shared definitions for the DNS cache-poisoning lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, zone data and the three resolver settings the lab turns on and off.
# Every other script sources it; never hardcode any of these in a second place.
#
# The lab is Layer 7: what the learner attacks is the caching resolver's rule for
# accepting a UDP answer, and what they defend is that same rule. The load-bearing
# facts here are the resolver's fixed outgoing source port, the delay in front of
# the authoritative server (which is the whole width of the race window), and the
# two addresses www.uni.lab can resolve to.

AS=107
DC=LAB
SW=S1

# ---------------------------------------------------------------------------
# Three subnets, one router between all of them.
#   campus : the resolver and the host that uses it, on a switched segment
#   auth   : the authoritative server for uni.lab, one point-to-point link away
#   hostile: the attacker, on a third link and on the path of neither of the above
#
# The attacker being on its own link is what makes the attack an OFF-PATH attack:
# it never sees the resolver's query to the authoritative server, so it cannot
# read the transaction ID or the source port off the wire and has to guess both.
# Every subnet lives inside the AS's 107.0.0.0/8 block, so subnet_config's
# AS-octet scheme still holds and every address is known before a container exists.
CAMPUS_SUBNET="107.1.0.0/24"    # resolver + victim (switched segment, via S1)
AUTH_SUBNET="107.2.0.0/24"      # authoritative server (point-to-point)
HOSTILE_SUBNET="107.3.0.0/24"   # attacker (point-to-point)
PREFIXLEN=24

ROUTER_CAMPUS_IP="107.1.0.1"    # router, campus side  (the campus hosts' default gateway)
ROUTER_AUTH_IP="107.2.0.1"      # router, auth side    (the auth server's default gateway)
ROUTER_HOSTILE_IP="107.3.0.1"   # router, hostile side (the attacker's default gateway)

RESOLVER_IP="107.1.0.10"        # the caching resolver under attack
VICTIM_IP="107.1.0.20"          # the host that asks the resolver and believes it
AUTH_IP="107.2.0.10"            # authoritative for uni.lab; the address the attacker forges
ATTACKER_IP="107.3.0.10"        # authoritative for attack.lab, and the poisoned answer

# ---------------------------------------------------------------------------
# The zone the attack is about, and the two answers it can produce.
#
# LEGIT_TTL is short on purpose. A cached answer cannot be poisoned, because a
# resolver holding one sends no query for anything to race; the attacker has to
# wait for the entry to expire. Sixty seconds keeps that wait to something a
# learner does in one sitting, and the handout has them watch the TTL count down
# so the wait is part of the lesson rather than dead time.
#
# POISON_TTL is the attacker's own choice, written into the forged answer. It is
# a day because nothing checks it: the resolver caps a cached TTL at
# max-cache-ttl (a week by default) and otherwise believes what it is told.
TARGET_ZONE="uni.lab"
TARGET_NAME="www.uni.lab"
LEGIT_TTL=60
POISON_TTL=86400

# The zone the attacker is authoritative for. Its only job is to be a name the
# resolver will look up on demand, so the resolver's outgoing query lands on the
# attacker's own interface where the attacker can read the source port off it.
PROBE_ZONE="attack.lab"

# ---------------------------------------------------------------------------
# The resolver's outgoing source port, fixed rather than randomised.
#
# This is weakness the whole of Part 1 rests on. A resolver accepts a UDP answer
# that matches the query's source address, its own source port, and the 16-bit
# transaction ID. Randomising the source port puts roughly another 16 bits in
# front of an off-path attacker; pinning it leaves the transaction ID alone,
# which is 65,536 values and a fraction of a second's work to sweep.
#
# BIND 9.18 still accepts `query-source ... port N` and warns that it is not
# recommended. That warning is the point: the lab starts from the configuration
# resolvers shipped with before 2008, and Part 2 has the learner remove it.
FIXED_QUERY_PORT=33333

# ---------------------------------------------------------------------------
# How far away the authoritative server is, in milliseconds.
#
# The race window is exactly this long: the resolver sends its query, and every
# forged answer that arrives before the real one is a chance to be believed. On a
# single laptop the round trip between two containers is a fraction of a
# millisecond, which would leave an off-path attacker a few dozen packets of
# window and no lab at all. AUTH_DELAY_MS reproduces the distance to an
# authoritative server on another continent, or one slow enough under load to
# take that long, by delaying its replies in a relay in front of it (slow-link,
# baked into the image). It is a stated fact in the handout, not a hidden knob:
# the learner measures it with dig's own "Query time" line and the arithmetic in
# Part 1 is done against the figure they measured.
#
# 400 ms with a sweep of the whole transaction-ID space measured at over 100,000
# packets per second means the sweep completes inside the window several times
# over, so the attack lands on the first attempt instead of being a coin flip a
# learner has to repeat. It is also comfortably under BIND's first retransmit, so
# the resolver asks once and the lab has one race to reason about, not several.
AUTH_DELAY_MS=400

# The HTTP identity each of the two candidate hosts serves on port 80. This is the
# data-plane oracle: the control plane says which address the resolver handed
# over, and curl says which machine actually answered.
AUTH_BANNER="the real www.uni.lab (authoritative host, ${AUTH_IP})"
ATTACKER_BANNER="IMPOSTOR: the attacker's host (${ATTACKER_IP})"
WEB_PORT=80

# ---------------------------------------------------------------------------
# Interface names.
#   Campus switched segment (resolver + victim + router <-> S1):
HOST_IF="${AS}-${SW}"           # each campus host's NIC, named after the switch
R_CAMPUS_IF="campus"            # router's campus-facing NIC
#   The two point-to-point links out of the campus:
R_AUTH_IF="auth"                # router, towards the authoritative server
R_HOSTILE_IF="hostile"          # router, towards the attacker
EXT_IF="${AS}-ext"              # the auth server's and the attacker's only NIC

# ---------------------------------------------------------------------------
SWITCH_IMAGE="miniinterneteth/d_switch"

HOST_IMAGE="d_host_dns"
# Open vSwitch is started explicitly instead of through the image's supervisord
# entrypoint, so that --no-mlockall can be passed. ovs-ctl locks ovs-vswitchd
# into memory by default. Under rootless Docker CAP_IPC_LOCK is confined to the
# user namespace and cannot exceed RLIMIT_MEMLOCK (8 MB on a stock host), so the
# first thread stack past that limit fails to lock and ovs-vswitchd dies with
# "pthread_create failed (Resource temporarily unavailable)". Locking buys this
# lab nothing: a lab switch forwards a handful of packets and never needs its
# pages pinned. Under rootful Docker the resulting datapath is identical.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# Container names follow the platform convention, with L7 marking the lab's layer:
# <AS>_L7_<DC>_<name>. One prefix covers every container (including the switch, an
# L2 device) so status/teardown can select the lab with a single filter.
SW_CTN="${AS}_L7_${DC}_${SW}"
ROUTER_CTN="${AS}_L7_${DC}_router"
RESOLVER_CTN="${AS}_L7_${DC}_resolver"
VICTIM_CTN="${AS}_L7_${DC}_victim"
AUTH_CTN="${AS}_L7_${DC}_auth"
ATTACKER_CTN="${AS}_L7_${DC}_attacker"

# The two hosts wired to the campus switch S1 (each takes HOST_IF). The router
# attaches to S1 too, through R_CAMPUS_IF; spawn handles it separately.
CAMPUS_HOSTS=(resolver victim)

# Every device that gets a starter config, in apply order: the router first so
# forwarding is up before anything crosses it, then the two name servers, then
# the resolver that queries them, then the victim that queries the resolver.
DEVICES=(router auth attacker resolver victim)

ctn_of()     { echo "${AS}_L7_${DC}_$1"; }
sw_port_of() { echo "${AS}-$1"; }

# Where each container keeps the files the lab reads or rewrites. Named here so
# the handout, the solution scripts, status.sh and selftest.sh cannot drift apart
# on a path.
NAMED_CONF="/etc/bind/named.conf"          # the resolver's and each server's main config
HARDENING_CONF="/etc/bind/hardening.conf"  # the three settings Part 2 rewrites, included by the above
TRUST_ANCHOR="/etc/bind/uni.lab.key"       # the zone's public key, handed to the resolver's operator
TRUST_ANCHOR_INSTALLED="/etc/bind/trust-anchors.conf"   # where the resolver reads it from, if at all
ZONE_FILE="/var/bind/uni.lab.zone"         # the authoritative server's unsigned zone source

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# Helpers the lifecycle scripts and selftest share, so neither repeats a docker
# incantation the other has to be kept in step with.

# What the resolver currently hands back for the lab's target name, asked as the
# victim asks it. Prints the address, or nothing when the resolver refuses or
# fails to answer.
resolved_address() {   # (no arguments)
    docker exec "$VICTIM_CTN" dig +short +timeout=3 +tries=1 \
        "@${RESOLVER_IP}" "$TARGET_NAME" A 2>/dev/null | grep -E '^[0-9.]+$' | head -1
}

# The rcode the resolver returns for that same question: NOERROR, SERVFAIL,
# REFUSED. The address alone cannot tell a validating resolver's refusal apart
# from a dead lab, and the difference is what Part 2c is about.
resolved_status() {   # (no arguments)
    docker exec "$VICTIM_CTN" dig +timeout=3 +tries=1 \
        "@${RESOLVER_IP}" "$TARGET_NAME" A 2>/dev/null \
        | sed -n 's/.*status: \([A-Z]*\).*/\1/p' | head -1
}

# Which machine actually answers an HTTP request for the target name, resolved
# through the resolver. Empty when nothing answers.
served_banner() {   # (no arguments)
    local ip
    ip="$( resolved_address )"
    [ -n "$ip" ] || return 0
    docker exec "$VICTIM_CTN" curl -s -m 5 "http://${ip}/" 2>/dev/null | head -1
}

# True while named is running in the given container.
named_running() {   # <ctn>
    docker exec "$1" pgrep -x named >/dev/null 2>&1
}

# Restart named and wait until it answers again. Used by reset.sh and by the
# solution scripts; the handout has the learner type the same two commands.
named_restart() {   # <ctn>
    docker exec "$1" sh -c 'pkill -x named 2>/dev/null; sleep 1; named -c '"$NAMED_CONF" >/dev/null 2>&1
    local _
    for _ in $(seq 1 40); do
        docker exec "$1" pgrep -x named >/dev/null 2>&1 && return 0
        sleep 0.25
    done
    return 1
}

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. Without this
# an image is only rebuilt when it is MISSING, which means an edit to image/ never
# reaches a machine that built the image once: the container keeps running the
# previous version and the handout describes tooling the learner does not have.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

# Image preflight, called by spawn.sh before the first `docker run`.
# The switch image is upstream and pulled; the host image is this lab's own and
# built from image/. Docker caches both, so every spawn after the first is a
# no-op here unless image/ has changed.
ensure_images() {
    if ! docker image inspect "$SWITCH_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] pulling $SWITCH_IMAGE (first run only)"
        docker pull "$SWITCH_IMAGE" >/dev/null \
            || { echo "failed to pull $SWITCH_IMAGE" >&2; return 1; }
    fi
    if ! docker image inspect "$HOST_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] building $HOST_IMAGE from $LAB_DIR/image (first run only)"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to build $HOST_IMAGE" >&2; return 1; }
    elif image_older_than_source "$HOST_IMAGE" "$LAB_DIR/image"; then
        echo "[spawn] rebuilding $HOST_IMAGE: $LAB_DIR/image changed since it was built"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to rebuild $HOST_IMAGE" >&2; return 1; }
    fi
}

# ---------------------------------------------------------------------------
# Privileged host networking, performed from a helper container.
#
# Wiring a lab needs privileges a learner's account will not have: CAP_NET_ADMIN
# to create a veth pair, and CAP_SYS_ADMIN to enter a container's network
# namespace and rename the interface inside it. Rather than require root on the
# host, a throwaway --privileged container holds them.
#
# The helper keeps a network namespace of its own (--network=none). Both ends of
# every veth pair are moved out into lab containers, so the namespace the pair is
# created in never matters. Asking for the host's namespace (--network=host)
# only breaks the helper under a rootless daemon, where that namespace belongs to
# a user namespace the helper holds no privilege in and every `ip link add`
# returns EPERM. --pid=host stays: it is what makes each lab container's
# /proc/<pid>/ns/net reachable for the moves.
#
# Renames run through `nsenter --net`, not `ip netns exec`. iproute2 remounts
# /sys on every namespace switch and a user namespace forbids that, while the
# rename itself is pure netlink and needs no sysfs at all.
HELPER_CTN="$( ctn_of netadmin_helper )"

helper_start() {
    docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true
    docker run -d --rm --name "$HELPER_CTN" \
        --privileged --network=none --pid=host \
        "$HOST_IMAGE" sleep 600 >/dev/null
    for _ in $(seq 1 40); do
        if docker exec "$HELPER_CTN" true >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    echo "helper container $HELPER_CTN did not become ready" >&2
    return 1
}

# Run one privileged networking command inside the helper.
helper() { docker exec "$HELPER_CTN" "$@"; }

helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }
