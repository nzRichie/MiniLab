#!/usr/bin/env bash
# Shared definitions for the malware command-and-control traffic analysis lab.
# Sourced by spawn/status/shell/reset/advance/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, interface names, service ports, intervals and file paths. Every
# other script sources it; never hardcode any of these in a second place.
#
# The lab is defender-only. One workstation on the inside runs an implant that
# checks in with a controller on the outside at a fixed interval. The learner
# never attacks anything: they capture at the gateway, tell the implant's flow
# apart from the periodic traffic that is supposed to be there, and then write
# the gateway's egress policy. The graded end state is that policy, measured by
# two facts at once -- the controller stops hearing from the implant, and the
# three legitimate services keep answering.
#
# WHICH WORKSTATION IS INFECTED IS AN ANSWER, and so is the controller's
# address. Both are named here because a lab script cannot work without them.
# Nothing the learner is pointed at prints either one: status.sh reports the
# controller by role and never by address, and the topology figure gives the
# outside hosts no addresses at all.

AS=118
DC=LAB

# ---------------------------------------------------------------------------
# Two segments meeting at the gateway.
#
#   inside  : three workstations and the gateway's inside NIC, over a switch.
#             Switched rather than point to point because the lab needs several
#             hosts producing traffic that arrives at the gateway mixed together.
#   outside : the two hosts that stand in for the internet, and the gateway's
#             outside NIC, over a switch of their own.
#
# The gateway FORWARDS (net.ipv4.ip_forward is 1) and does not translate
# addresses. That is load-bearing rather than a shortcut: with no NAT, every
# packet that crosses the gateway still carries the workstation's own source
# address, so a capture taken there says which inside host produced each flow.
# Behind a NAT the whole exercise would collapse to one source address.
INSIDE_SUBNET="118.0.0.0/24"
OUTSIDE_SUBNET="118.1.0.0/24"
PREFIXLEN=24

GW_INSIDE_IP="118.0.0.1"
GW_OUTSIDE_IP="118.1.0.1"

WS1_IP="118.0.0.21"
WS2_IP="118.0.0.32"
WS3_IP="118.0.0.43"

# ---------------------------------------------------------------------------
# The outside addresses.
#
# Five addresses on two containers, and the split between them carries no
# information: ext1 holds two legitimate services, ext2 holds one legitimate
# service and the controller. A learner who works out which container an address
# sits on has learned nothing about which address is the controller, which is the
# point of arranging them this way.
#
# ext1
MIRROR_IP="118.1.0.10"       # the package mirror; every workstation fetches from it
DOCS_IP="118.1.0.30"         # an internal documentation site
# ext2
HEALTH_IP="118.1.0.20"       # the monitoring endpoint two workstations poll
C2_IP="118.1.0.66"           # THE CONTROLLER, stages 1 and 2
C2_MOVED_IP="118.1.0.99"     # where it moves in stage 3; added to ext2 by advance.sh

# Every legitimate destination, which is also exactly the allowlist Part 5 ends
# with. Named once here so status.sh, selftest.sh and solution/apply.sh cannot
# disagree about what "legitimate" means.
LEGIT_IPS=("$MIRROR_IP" "$HEALTH_IP" "$DOCS_IP")
WEB_PORT=80

# ---------------------------------------------------------------------------
# The implant, and the three stages the incident runs through.
#
# Stage 1  HTTP POST to the controller on tcp/8080, every BEACON_INTERVAL
#          seconds with no variation at all, a request body of exactly
#          BEACON_BODY_BYTES bytes and a reply of exactly BEACON_REPLY_BYTES.
#          Every one of those is a signal, and the lab takes them away one at a
#          time.
# Stage 2  the same implant over TLS on tcp/443, with the interval drawn afresh
#          each time between BEACON_JITTER_MIN and BEACON_JITTER_MAX. The port
#          and the readable payload are gone; the destination and the shape of
#          the flow are not.
# Stage 3  the controller moves to an address that has never appeared in any
#          capture the learner has taken. Nothing about the implant changes.
#          This is what a rule naming one destination cannot survive and an
#          allowlist can.
BEACON_INTERVAL=30
BEACON_JITTER_MIN=18         # 30 seconds minus 40 percent
BEACON_JITTER_MAX=42         # 30 seconds plus 40 percent
BEACON_BODY_BYTES=96
BEACON_REPLY_BYTES=64
BEACON_PATH="/api/v1/status"
BEACON_FIRST_DELAY=7         # seconds after the implant starts before check-in 1

C2_HTTP_PORT=8080
C2_TLS_PORT=443

# The stage the incident is currently at, on the infected workstation, and the
# implant's configuration file beside it. The implant re-reads the stage between
# check-ins, so advance.sh changes a stage by writing a digit rather than by
# restarting anything.
BEACON_DIR="/etc/minilabs"
BEACON_STAGE_FILE="${BEACON_DIR}/beacon.stage"
BEACON_CONF="${BEACON_DIR}/beacon.conf"
BEACON_MAX_STAGE=3

# ---------------------------------------------------------------------------
# The periodic traffic that is SUPPOSED to be there, and the reason Part 2 is an
# exercise rather than a lookup.
#
# All three workstations poll a monitoring endpoint on exactly the same period
# as the implant's stage 1 interval, the infected one included. Regularity on
# its own therefore picks out four flows, not one, and the infected workstation
# looks exactly like the other two except for one extra flow. What separates the
# check-in from the polls is that the monitoring endpoint is polled by three
# hosts and the controller by one, that the poll's reply varies in length while
# the check-in's does not, and that the check-in sends more bytes than it
# receives while every other flow in the lab does the opposite.
#
# The polls start at different offsets so the periodic flows do not arrive in
# lockstep, which would make a capture read as one event rather than four.
POLL_INTERVAL=30
POLL_PATH="/health"
WS1_POLL_OFFSET=3
WS2_POLL_OFFSET=17
WS3_POLL_OFFSET=25

# The browsing noise: a request to one of the two sites every BROWSE_MIN to
# BROWSE_MAX seconds, to a path drawn from the site's own list. Its gaps are
# short and uneven and its replies vary in size, which is what makes the three
# periodic flows stand out from it at all.
BROWSE_MIN=3
BROWSE_MAX=17

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<segment>
# convention. The gateway names each of its two NICs after the segment it faces;
# the three workstations share a segment and therefore share an interface name,
# and what distinguishes them at the switch is the port name below.
WS_IF="${AS}-lan"
EXT_IF="${AS}-ext"
GW_INSIDE_IF="lan"
GW_OUTSIDE_IF="ext"

# One switch per segment, rather than two bridges inside one switch container.
# Two bridges in one Open vSwitch instance would behave identically -- they are
# two broadcast domains and do not forward between each other -- and would draw
# as a single box that every machine in the lab connects to. The one fact this
# lab is built on is that the ONLY path from inside to outside is through the
# gateway, and a topology figure that appears to contradict it is worse than one
# more container.
SW_IN="S1"
SW_OUT="S2"
SW_IN_CTN="${AS}_L7_${DC}_${SW_IN}"
SW_OUT_CTN="${AS}_L7_${DC}_${SW_OUT}"
SWITCHES=(S1 S2)
BR="br0"
sw_port_of() { echo "${AS}-$1"; }        # 118-gwlan, 118-ws1, 118-ext1, ...

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L7 marking the lab's
# layer: <AS>_L7_<DC>_<name>. The names deliberately say nothing about what a
# machine does: ws1, ws2 and ws3 are interchangeable from the outside, and ext1
# and ext2 both hold legitimate services.
GW_CTN="${AS}_L7_${DC}_gw"
WS1_CTN="${AS}_L7_${DC}_ws1"
WS2_CTN="${AS}_L7_${DC}_ws2"
WS3_CTN="${AS}_L7_${DC}_ws3"
EXT1_CTN="${AS}_L7_${DC}_ext1"
EXT2_CTN="${AS}_L7_${DC}_ext2"

# The infected workstation. An answer; see the header.
INFECTED=ws3
INFECTED_CTN="$WS3_CTN"
INFECTED_IP="$WS3_IP"

WORKSTATIONS=(ws1 ws2 ws3)

# Every device that gets a starter config, in apply order: the outside services
# first so there is something to fetch, then the gateway that routes to them,
# then the workstations whose traffic generators start last and immediately have
# somewhere to send traffic.
DEVICES=(ext1 ext2 gw ws1 ws2 ws3)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

ip_of() {   # <role> -> its inside/outside address
    case "$1" in
        gw)   echo "$GW_INSIDE_IP" ;;
        ws1)  echo "$WS1_IP" ;;
        ws2)  echo "$WS2_IP" ;;
        ws3)  echo "$WS3_IP" ;;
        ext1) echo "$MIRROR_IP" ;;
        ext2) echo "$HEALTH_IP" ;;
        *)    echo "" ;;
    esac
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_c2"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed". --no-mlockall is what
# makes this lab boot on a rootless daemon.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# The controller's record of what reached it.
#
# One line per check-in: epoch seconds, the source address the request came
# from, the port it arrived on, and the number of bytes in the request body.
# This is the lab's headline oracle. It is read from the controller rather than
# from the implant on purpose: the question a containment rule answers is not
# whether the implant tried, it is whether anything arrived.
C2_LOG="/var/log/c2/checkins.log"
C2_CERT="/etc/minilabs/c2.pem"

# ---------------------------------------------------------------------------
# The learner's egress policy, on the gateway.
#
# One table, created by the learner and removed by reset.sh. The chain is named
# `forward` rather than `fwd` because `fwd` is an nft keyword (the netdev
# forward statement) and a chain by that name is a syntax error in every command
# that mentions it afterwards.
NFT_TABLE="egress"
NFT_CHAIN="forward"

# ---------------------------------------------------------------------------
# Capture defaults the handout quotes. The first capture is an inventory and 60
# seconds of it is enough to see every destination; the second is a measurement
# of how regularly a flow repeats, and 180 seconds is what gives five or six
# gaps to average over rather than two.
CAP_INVENTORY_SECS=60
CAP_MEASURE_SECS=180
CAP_FILE="/tmp/egress.pcap"

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

# Image preflight, called by spawn.sh before the first `docker run`. The switch
# image is pulled rather than built; the host image is this lab's own.
ensure_images() {
    if ! docker image inspect "$HOST_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] building $HOST_IMAGE from $LAB_DIR/image (first run only)"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to build $HOST_IMAGE" >&2; return 1; }
    elif image_older_than_source "$HOST_IMAGE" "$LAB_DIR/image"; then
        echo "[spawn] rebuilding $HOST_IMAGE: $LAB_DIR/image changed since it was built"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to rebuild $HOST_IMAGE" >&2; return 1; }
    fi
    if ! docker image inspect "$SWITCH_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] pulling $SWITCH_IMAGE (first run only)"
        docker pull "$SWITCH_IMAGE" >/dev/null \
            || { echo "failed to pull $SWITCH_IMAGE" >&2; return 1; }
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

# ---------------------------------------------------------------------------
# Shared read-only probes. status.sh and selftest.sh both need these, and a
# second copy of any of them is a chance for the two to disagree about what the
# lab's success condition is.

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# --- the controller's side -------------------------------------------------

# How many check-ins reached the controller in the last <n> seconds. `awk` does
# the comparison rather than `tail`, because the interesting count is over a
# window and not over a number of lines.
checkins_since() {   # <seconds>
    local now; now="$( date +%s )"
    docker exec "$EXT2_CTN" awk -v t="$(( now - $1 ))" \
        '$1 + 0 >= t { c++ } END { print c + 0 }' "$C2_LOG" 2>/dev/null || echo 0
}

checkins_total() {
    docker exec "$EXT2_CTN" awk 'END { print NR + 0 }' "$C2_LOG" 2>/dev/null || echo 0
}

# Seconds since the last check-in, or "" when there has never been one. This is
# the number that says whether a containment rule is holding, because it keeps
# growing for as long as nothing arrives.
last_checkin_age() {
    local now last
    now="$( date +%s )"
    last="$( docker exec "$EXT2_CTN" awk 'END { print $1 + 0 }' "$C2_LOG" 2>/dev/null )"
    case "$last" in ''|0) echo ""; return 0 ;; esac
    echo $(( now - last ))
}

# The source address of the last check-in, and the port it arrived on. Used by
# selftest to prove the implant is the machine the answer key says it is; never
# printed by status.sh, which would hand over both answers at once.
last_checkin_src()  { docker exec "$EXT2_CTN" awk 'END { print $2 }' "$C2_LOG" 2>/dev/null; }
last_checkin_port() { docker exec "$EXT2_CTN" awk 'END { print $3 }' "$C2_LOG" 2>/dev/null; }
last_checkin_bytes(){ docker exec "$EXT2_CTN" awk 'END { print $4 + 0 }' "$C2_LOG" 2>/dev/null; }

# The gaps between consecutive check-ins, in seconds, one per line. The whole of
# Part 2 is a claim about this list.
checkin_gaps() {
    docker exec "$EXT2_CTN" awk 'NR > 1 { print $1 - p } { p = $1 }' "$C2_LOG" 2>/dev/null
}

c2_listener_running() {
    docker exec "$EXT2_CTN" sh -c 'pgrep -f c2listener.py >/dev/null 2>&1'
}

# --- the implant's side ----------------------------------------------------

beacon_stage() {
    docker exec "$INFECTED_CTN" cat "$BEACON_STAGE_FILE" 2>/dev/null | tr -dc '0-9'
}

beacon_running() {
    docker exec "$INFECTED_CTN" sh -c 'pgrep -f beacon.sh >/dev/null 2>&1'
}

# --- the gateway's side ----------------------------------------------------

# The whole ruleset as the learner wrote it, or "" when they have written none.
nft_ruleset() {
    docker exec "$GW_CTN" nft list ruleset 2>/dev/null | grep -v '^[[:space:]]*$' || true
}

nft_table_present() {
    docker exec "$GW_CTN" sh -c "nft list table inet $NFT_TABLE >/dev/null 2>&1"
}

# The forward chain's policy: accept, drop, or "" when there is no such chain.
# The distinction between a chain that drops by default and one that accepts by
# default is the whole difference between Part 5 and Part 3.
nft_forward_policy() {
    docker exec "$GW_CTN" nft -a list ruleset 2>/dev/null \
        | awk '/type filter hook forward/ { for (i = 1; i <= NF; i++) if ($i == "policy;") next
               if (match($0, /policy [a-z]+/)) { s = substr($0, RSTART + 7); sub(/;.*/, "", s); print s; exit } }'
}

# Whether any rule in the ruleset names a given address at all. Used to report
# what a policy is written against without judging it.
nft_mentions() {   # <address>
    docker exec "$GW_CTN" sh -c "nft list ruleset 2>/dev/null | grep -q '$1'"
}

# --- what still works ------------------------------------------------------

# The HTTP status code a workstation gets for one URL, or 000 when the transfer
# never produced a status line, which is what a dropped SYN looks like once curl
# runs out of patience.
#
# The output is captured and inspected rather than guarded with `|| echo 000`.
# curl WRITES its -w line even when the transfer failed, and then exits non-zero,
# so the fallback fired on top of a value curl had already printed and the caller
# got "000000". A code is three digits or it is not a code.
http_code() {   # <role> <url>
    local out
    out="$( docker exec "$( ctn_of "$1" )" curl -s -o /dev/null -m 6 -w '%{http_code}' "$2" 2>/dev/null )"
    case "$out" in
        [0-9][0-9][0-9]) echo "$out" ;;
        *)               echo 000 ;;
    esac
}

mirror_code() { http_code "${1:-ws1}" "http://${MIRROR_IP}/index.html"; }
docs_code()   { http_code "${1:-ws1}" "http://${DOCS_IP}/index.html"; }
health_code() { http_code "${1:-ws1}" "http://${HEALTH_IP}${POLL_PATH}"; }

# True when all three legitimate services answer a workstation with 200. This is
# the liveness half of the oracle, and it is what stops a blanket egress drop
# from passing as containment.
legit_all_ok() {   # [role]
    local r="${1:-ws1}"
    [ "$( mirror_code "$r" )" = 200 ] && [ "$( docs_code "$r" )" = 200 ] \
        && [ "$( health_code "$r" )" = 200 ]
}
