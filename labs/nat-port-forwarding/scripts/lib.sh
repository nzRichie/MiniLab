#!/usr/bin/env bash
# Shared definitions for the NAT and port-forwarding lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, interface names, service ports, markers and file paths. Every other
# script sources it; never hardcode any of these in a second place.
#
# The lab is a configuration exercise. A site sits behind one edge router: three
# machines on a private prefix that no other network routes, and one machine on
# the far side that stands in for everything the site is not. The router forwards
# between the two and translates nothing, which is a site whose traffic leaves and
# whose replies never come back. Every rule that fixes that is written by the
# learner, on the router, in nftables.

AS=112
DC=LAB
SW=S1

# ---------------------------------------------------------------------------
# Two segments, one router between them.
#
# The inside prefix is deliberately taken from RFC 1918's 192.168/16 rather than
# from this AS's own 112.0.0.0/8 block, because the whole lab rests on the
# outside having no route back to it. An address the far side cannot reach is not
# a quirk of this topology, it is the property that makes address translation
# necessary at all, and picking the prefix from the space reserved for exactly
# that purpose is what keeps the lab honest about why.
#
# The outside segment does come out of the AS block, so the AS-octet scheme in
# platform/config/subnet_config.sh holds for the half of the lab that is meant to
# be globally reachable.
INSIDE_SUBNET="192.168.10.0/24"
OUTSIDE_SUBNET="112.0.0.0/24"
PREFIXLEN=24

ROUTER_IN_IP="192.168.10.1"    # router, inside  (every private host's default gateway)
ROUTER_OUT_IP="112.0.0.1"      # router, outside (the one address the site is seen as)

INSIDE1_IP="192.168.10.11"     # a client on the private segment
INSIDE2_IP="192.168.10.12"     # a second client, so two flows can collide on purpose
WEB_IP="192.168.10.20"         # the private web service Part 4 publishes
OUTSIDE_IP="112.0.0.10"        # the host beyond the edge

# The outside host is given the connected route for its own segment and NOTHING
# else: no default route, and no route to 192.168.10.0/24. That single omission
# is Part 1's entire lesson, and it is what a real internet host looks like from
# the point of view of a private prefix. A default route pointed back at the
# router would carry replies home and there would be no lab.

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs on the private segment follow the platform's
# <AS>-<SW> convention, because they all plug into the same switch; the router
# names each of its two NICs after the side it faces, so every rule the learner
# writes reads as `oifname "outside"` rather than as an interface number they
# have to look up.
HOST_IF="${AS}-${SW}"          # inside-1, inside-2, webserver: the switch-facing NIC
OUT_IF="${AS}-ext"             # the outside host's only NIC

R_IN_IF="inside"               # router, facing the private segment
R_OUT_IF="outside"             # router, facing the outside host

# The switch names each port after the device on the other end of it.
sw_port_of() { echo "${AS}-$1"; }

# ---------------------------------------------------------------------------
# The two web services, and the marker each one serves.
#
# Both markers are distinctive strings that appear nowhere else in the lab, so a
# fetch that returns one is unambiguous evidence of WHICH service answered. That
# matters more here than in a lab with one server: after Part 4 the same client
# can reach two different web services through two different addresses, and
# "curl printed a page" does not say which.
OUTSIDE_MARKER="OUTSIDE-SITE-3D18B4"
INSIDE_MARKER="INSIDE-SITE-9C40FA"

WEB_ROOT="/var/www/localhost/htdocs"

# The port both web services listen on, and the port the router publishes the
# private one on. They differ on purpose: the outside port and the inside port of
# a forward are independent values, and a learner who only ever sees 80 mapped to
# 80 comes away thinking a port forward is an address rewrite with the port
# carried along.
WEB_PORT=80
PUBLIC_PORT=8080

# The endpoint both web services expose beside their marker, and the whole of
# this lab's instrumentation on the server side. It returns the source address of
# the connection the server is answering, in the response body, so a client reads
# it with one curl and no second shell.
#
# That address is the answer to nearly every question the lab asks. With no
# translation it is the private client's own address, and the reply never
# arrives. After source NAT the outside server reports the router. After
# destination NAT the inside server reports the real outside client, because
# destination NAT rewrites the destination and leaves the source alone. After the
# hairpin rule it reports the router again, for a client three metres away.
WHOAMI_PATH="/whoami.cgi"

# lighttpd's own access log. It records the same address in its first field and
# it is where an administrator would look, so status.sh prints it; nothing is
# graded on it, because mod_accesslog flushes on a timer and a line can be a
# second behind the request that produced it.
ACCESS_LOG="/var/log/lighttpd/access.log"
LIGHTTPD_CONF="/etc/lighttpd/lighttpd.conf"
LIGHTTPD_PID="/run/lighttpd.pid"

# ---------------------------------------------------------------------------
# The source port both private clients are told to pin a connection to, so that
# two flows arrive at the router identical in every field a NAPT mapping is keyed
# on except the source address.
#
# A masquerade rule leaves the source port alone when it can, so two clients
# picking ephemeral ports at random almost never collide and a learner watching
# only that sees a table of recorded ports and no rewriting at all. Pinning both
# to one port forces the rewrite that proves the router is translating the
# transport identifier and not merely the address.
COLLIDE_PORT=40000

# ---------------------------------------------------------------------------
# The nftables objects the learner builds. Named here so status.sh can report on
# them by the same names the handout tells the learner to type.
NFT_FAMILY="ip"
NFT_TABLE="nat"
NFT_PRE="prerouting"
NFT_POST="postrouting"

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L3 marking the lab's
# layer: <AS>_L3_<DC>_<name>. The switch carries the same prefix as the hosts
# even though it is a Layer 2 device, so status and teardown select the whole lab
# with a single filter.
ROUTER_CTN="${AS}_L3_${DC}_router"
INSIDE1_CTN="${AS}_L3_${DC}_inside-1"
INSIDE2_CTN="${AS}_L3_${DC}_inside-2"
WEB_CTN="${AS}_L3_${DC}_webserver"
OUTSIDE_CTN="${AS}_L3_${DC}_outside"
SW_CTN="${AS}_L3_${DC}_${SW}"

ctn_of() { echo "${AS}_L3_${DC}_$1"; }

# Every device, in the order spawn configures them: the router first, so both
# segments are addressed before anything crosses them.
DEVICES=(router webserver outside inside-1 inside-2)

# The three devices that plug into the inside switch, and the switch port each
# one lands on.
INSIDE_HOSTS=(inside-1 inside-2 webserver)

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_nat"
SWITCH_IMAGE="miniinterneteth/d_switch"

# ovs-ctl rather than the image's supervisord entrypoint, and --no-mlockall
# rather than the default: under a rootless daemon CAP_IPC_LOCK cannot exceed
# RLIMIT_MEMLOCK, thread stacks fail to lock, and ovs-vswitchd dies with
# pthread_create failed before the bridge ever exists.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# otherwise only rebuilt when it is missing, which means an edit to
# image/Dockerfile never reaches a machine that built the image once: the
# container keeps running the previous version and the handout describes tooling
# the learner does not have.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

# Image preflight, called by spawn.sh before the first `docker run`.
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
# created in never matters. Asking for the host's namespace (--network=host) only
# breaks the helper under a rootless daemon, where that namespace belongs to a
# user namespace the helper holds no privilege in and every `ip link add` returns
# EPERM. --pid=host stays: it is what makes each lab container's
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

# ---------------------------------------------------------------------------
# Shared read-only probes. status.sh and selftest.sh both need these, and a
# second copy of any of them is a chance for the two to disagree about what the
# lab's success condition is.

# Run a command on a lab device by role name.
on() {   # <role> <cmd...>
    local role="$1"; shift
    docker exec "$( ctn_of "$role" )" "$@"
}

# Percentage of echo replies lost, for three requests. Prints a bare number, or
# the empty string when ping produced no statistics line at all.
#
# 100 and the empty string mean different things and both occur here: 100 is
# "the requests went out and nothing came back", which is Part 1's whole point,
# and empty is "ping never ran", which is a broken lab.
ping_loss() {   # <role> <target>
    docker exec "$( ctn_of "$1" )" sh -c \
        "ping -c 3 -W 2 '$2' 2>/dev/null | sed -n 's/.*, \\([0-9]*\\)% packet loss.*/\\1/p'"
}

# The body a fetch returned, empty when the fetch failed for any reason.
http_body() {   # <role> <url>
    docker exec "$( ctn_of "$1" )" curl -s --max-time 8 "$2" 2>/dev/null
}

# curl's exit status for the same fetch: 0 on success, 7 when the connection was
# refused or the network was unreachable, 28 when it timed out with no answer.
# Those three are the whole of what this lab's failures look like from a client,
# and telling them apart is what says which translation is missing.
http_status() {   # <role> <url>
    docker exec "$( ctn_of "$1" )" sh -c \
        "curl -s -o /dev/null --max-time 8 '$2' >/dev/null 2>&1; echo \$?"
}

# curl's own message for a failed fetch, which names the cause in words where the
# exit status does not.
http_message() {   # <role> <url>
    docker exec "$( ctn_of "$1" )" sh -c \
        "curl -sS -o /dev/null --max-time 8 '$2' 2>&1 | head -1"
}

# The reason curl -v gives for a connection that never opened, reduced to the two
# or three words that name it: "Connection refused" when something answered the
# SYN with a reset, "Network unreachable" when the packet never left the host
# because no route covered the destination.
#
# curl's summary line collapses both into "Could not connect to server" and both
# into exit status 7, so the summary cannot tell a learner which of the two
# happened, and the two failures have different causes and different fixes. The
# verbose line is the only place curl distinguishes them.
#
# Prints the empty string when the connection opened, or when it opened and then
# timed out, which is a third outcome again.
connect_reason() {   # <role> <url>
    docker exec "$( ctn_of "$1" )" sh -c \
        "curl -sv -o /dev/null --max-time 8 '$2' 2>&1 \
         | sed -n 's/^\* .*[Cc]onnect.*: \(.*\)$/\1/p' | head -1" | tr -d '\r'
}

# The source address a web service saw, fetched from <role> through <url>. The
# url is the whoami endpoint on whichever server the fetch is meant to reach, so
# this measures the translation as the receiving server experiences it.
#
# This is the lab's central measurement: the same fetch produces a different
# value depending on which translations the router is performing, and no other
# observable distinguishes them. Empty means the fetch itself failed, which is a
# different outcome from a fetch that succeeded and reported an unexpected
# address, and the two are never conflated.
seen_source() {   # <role> <url>
    docker exec "$( ctn_of "$1" )" sh -c \
        "curl -s --max-time 8 '$2' 2>/dev/null | tr -d '\r' | head -1"
}

# The last line of a web service's access log, for status.sh to print as
# supporting evidence.
last_log_line() {   # <role>
    docker exec "$( ctn_of "$1" )" sh -c "tail -1 '$ACCESS_LOG' 2>/dev/null"
}

# The router's whole nftables ruleset, for status.sh to print.
nat_ruleset() {
    docker exec "$ROUTER_CTN" nft list ruleset 2>/dev/null
}

# The connection-tracking table on the router, optionally filtered. Printed
# without the `[ASSURED]`-style flags so the two tuples on each line are what a
# reader's eye lands on.
conntrack_rows() {   # [conntrack args...]
    docker exec "$ROUTER_CTN" conntrack -L "$@" 2>/dev/null
}

# Everything conntrack holds is thrown away. A NAT rule is consulted only for the
# first packet of a connection, so a flow that was tracked before a rule existed
# keeps going untranslated until its entry expires; clearing the table is what
# makes an experiment repeatable.
conntrack_flush() {
    docker exec "$ROUTER_CTN" conntrack -F >/dev/null 2>&1 || true
}

# What <role>'s routing table does with a destination, in one line. On the
# outside host this is how "there is no route into the private prefix" stops
# being an assertion and becomes something the machine says itself.
route_get() {   # <role> <address>
    docker exec "$( ctn_of "$1" )" sh -c "ip route get '$2' 2>&1 | head -1"
}

# True when lighttpd on <role> is listening on the port it serves.
web_is_listening() {   # <role>
    docker exec "$( ctn_of "$1" )" netstat -tln 2>/dev/null \
        | awk -v p=":${WEB_PORT}" '$1 == "tcp" && $4 ~ p"$" { found = 1 } END { exit !found }'
}

# True when the router's ruleset holds a chain hooked at <hook>.
#
# The grep runs inside the container and its result is captured before it is
# tested. A `docker exec ... | grep -q` pipeline looks equivalent and is not:
# grep -q exits at the first match, docker exec takes SIGPIPE, and under
# `set -o pipefail` the caller reads that as a failure on every successful match.
has_nat_chain() {   # <prerouting|postrouting>
    local hit
    hit="$( docker exec "$ROUTER_CTN" sh -c \
        "nft list table ${NFT_FAMILY} ${NFT_TABLE} 2>/dev/null | grep -c 'hook $1'" | tr -d '\r' )"
    case "$hit" in ''|0|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# True when the router's ruleset holds a rule carrying <text>.
has_nat_rule() {   # <substring>
    local hit
    hit="$( docker exec "$ROUTER_CTN" sh -c \
        "nft list table ${NFT_FAMILY} ${NFT_TABLE} 2>/dev/null | grep -c -F -- '$1'" | tr -d '\r' )"
    case "$hit" in ''|0|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# ---------------------------------------------------------------------------
# The three fetches the lab is graded on, named once so status.sh, selftest.sh
# and the reference solution cannot disagree about what "working" means.
#
#   outbound  a private client reaching the far side. Needs source NAT.
#   inbound   the far side reaching the private web service through the router's
#             own address. Needs destination NAT.
#   hairpin   a private client reaching that same published address. Needs the
#             destination NAT to match traffic from its own side, AND a second
#             source NAT so the reply comes back the way it went out.
OUTBOUND_URL="http://${OUTSIDE_IP}/"
PUBLISHED_URL="http://${ROUTER_OUT_IP}:${PUBLIC_PORT}/"
DIRECT_WEB_URL="http://${WEB_IP}/"

# The same three, aimed at the whoami endpoint instead of the marker.
OUTBOUND_WHOAMI="http://${OUTSIDE_IP}${WHOAMI_PATH}"
PUBLISHED_WHOAMI="http://${ROUTER_OUT_IP}:${PUBLIC_PORT}${WHOAMI_PATH}"
DIRECT_WEB_WHOAMI="http://${WEB_IP}${WHOAMI_PATH}"
