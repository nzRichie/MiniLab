#!/usr/bin/env bash
# Shared definitions for the DNS tunnelling and egress control lab.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, interface names, zone names and file paths. Every other script
# sources it; never hardcode any of these in a second place.
#
# The lab is played attacker then defender. On the inside an operator has a
# foothold on one workstation and moves a file out of a network that permits DNS
# and blocks every other outbound connection, by encoding the file's bytes into
# the names of DNS queries for a zone whose authoritative server sits outside.
# The learner drives that channel by hand in Part 1, then in Part 2 writes the
# configuration that closes it: first the gateway's DNS egress policy, and then,
# once the channel moves onto the sanctioned resolver where a port rule cannot
# reach it, a response policy on the resolver itself.
#
# The graded end state is that configuration, measured by two facts at once: the
# outside collector receives zero decoded bytes on either transport, and a
# legitimate name (example.lab) still resolves through the resolver.

AS=119
DC=LAB

# ---------------------------------------------------------------------------
# Two segments meeting at the gateway.
#
#   inside  : the sanctioned resolver, two workstations, and the gateway's
#             inside NIC, over a switch.
#   outside : the two hosts that stand in for the internet -- a legitimate
#             authoritative server and the operator's authoritative server that
#             doubles as the collector -- and the gateway's outside NIC, over a
#             switch of their own.
#
# The gateway FORWARDS (net.ipv4.ip_forward is 1) and does not translate
# addresses. With no NAT every packet that crosses the gateway still carries the
# inside host's own source address, so a capture taken there says which inside
# host produced each query, and the collector's own record does too. Behind a
# NAT every query would carry the gateway's address and the whole exercise would
# collapse to one source.
INSIDE_SUBNET="119.0.0.0/24"
OUTSIDE_SUBNET="119.1.0.0/24"
PREFIXLEN=24

GW_INSIDE_IP="119.0.0.1"
GW_OUTSIDE_IP="119.1.0.1"

RESOLVER_IP="119.0.0.2"       # the sanctioned recursive resolver
WS1_IP="119.0.0.23"           # the compromised workstation; the learner works here in Part 1
WS2_IP="119.0.0.34"           # a clean workstation; the legitimate-DNS baseline

# ---------------------------------------------------------------------------
# The outside addresses.
PUB_IP="119.1.0.10"           # legitimate authoritative server for example.lab
COLLECTOR_IP="119.1.0.66"     # the operator's authoritative server for evil.lab,
                              # and the machine that decodes and counts what arrives

# Every legitimate outbound DNS destination the resolver must keep reaching. Part
# 2 must not break these. Named once so status.sh, selftest.sh and the solution
# scripts cannot disagree about what "legitimate" means.
WEB_PORT=80
DNS_PORT=53

# ---------------------------------------------------------------------------
# The zones.
#
#   example.lab   a legitimate external zone, authoritative on pub. Resolving
#                 www.example.lab through the resolver is the check that the
#                 defence did not break ordinary name resolution.
#   evil.lab      the operator's zone, authoritative on the collector. The file
#                 leaves inside the names of queries under t.evil.lab.
#
# The resolver reaches both by recursion from a small root zone it serves itself
# (there is no separate root container): the root delegates example.lab to pub
# and evil.lab to the collector, exactly as the real root would delegate a
# registered domain to whoever registered it. That the operator's own zone is
# reachable by normal recursion is the whole reason Part 2A's port rule is not
# enough and Part 2B's response policy is.
LEGIT_ZONE="example.lab"
LEGIT_NAME="www.example.lab"
LEGIT_NS="ns.example.lab"

TUNNEL_ZONE="evil.lab"
TUNNEL_NS="ns.evil.lab"
TUNNEL_LABEL="t.${TUNNEL_ZONE}"     # data chunks are queried as <chunk>.<seq>.t.evil.lab

# The collector's record of what reached it. One line per query it received under
# t.evil.lab: epoch seconds, the source address the query came from, the
# sequence label, the data label, and the number of base32 characters in it.
# Read from the collector, not from the workstation: the question a containment
# rule answers is not whether the channel tried, it is whether anything arrived.
TUNNEL_LOG="/var/log/tunnel/received.log"
TUNNEL_DIR="/var/log/tunnel"

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<segment>
# convention. The gateway names each of its two NICs after the segment it faces;
# the inside hosts share a segment and therefore share an interface name, and
# what distinguishes them at the switch is the port name below.
LAN_IF="${AS}-lan"
EXT_IF="${AS}-ext"
GW_INSIDE_IF="lan"
GW_OUTSIDE_IF="ext"

# One switch per segment, so no port of one is a port of the other and the only
# path from inside to outside is through the gateway.
SW_IN="S1"
SW_OUT="S2"
SW_IN_CTN="${AS}_L7_${DC}_${SW_IN}"
SW_OUT_CTN="${AS}_L7_${DC}_${SW_OUT}"
SWITCHES=(S1 S2)
BR="br0"
sw_port_of() { echo "${AS}-$1"; }        # 119-gwlan, 119-resolver, 119-pub, ...

# ---------------------------------------------------------------------------
# Container names: <AS>_L7_<DC>_<name>.
GW_CTN="${AS}_L7_${DC}_gw"
RESOLVER_CTN="${AS}_L7_${DC}_resolver"
WS1_CTN="${AS}_L7_${DC}_ws1"
WS2_CTN="${AS}_L7_${DC}_ws2"
PUB_CTN="${AS}_L7_${DC}_pub"
COLLECTOR_CTN="${AS}_L7_${DC}_collector"

# Inside hosts other than the gateway (workstations and the resolver).
INSIDE_HOSTS=(resolver ws1 ws2)
OUTSIDE_HOSTS=(pub collector)

# Every device that gets a starter config, in apply order: the outside
# authoritative servers first so there is something to resolve, then the
# resolver, then the gateway that routes and filters between the two segments,
# then the workstations.
DEVICES=(pub collector resolver gw ws1 ws2)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

ip_of() {   # <role> -> its address
    case "$1" in
        gw)        echo "$GW_INSIDE_IP" ;;
        resolver)  echo "$RESOLVER_IP" ;;
        ws1)       echo "$WS1_IP" ;;
        ws2)       echo "$WS2_IP" ;;
        pub)       echo "$PUB_IP" ;;
        collector) echo "$COLLECTOR_IP" ;;
        *)         echo "" ;;
    esac
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_dnstun"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed". --no-mlockall is what
# makes this lab boot on a rootless daemon.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# The learner's egress policy, on the gateway.
#
# The gateway arrives with a starter policy that already blocks general outbound
# and permits only DNS, which is the environment the channel exploits. Part 2A
# narrows that DNS permission to the resolver alone. The table is named `egress`
# and the forward chain `forward` -- not `fwd`, which is an nft keyword.
NFT_TABLE="egress"
NFT_CHAIN="forward"

# The resolver's response policy, on the resolver (Part 2B). Written by the
# learner; reset.sh removes it by re-applying the starter config.
RPZ_ZONE="rpz.block"

# Capture defaults the handout quotes.
CAP_SECS=30
CAP_FILE="/tmp/egress.pcap"

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# otherwise only rebuilt when it is missing, which means an edit to
# image/Dockerfile never reaches a machine that built the image once.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

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
# Privileged host networking, performed from a helper container. See c2-beaconing
# for the full reasoning; the contract is identical.
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

helper() { docker exec "$HELPER_CTN" "$@"; }
helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }

# ---------------------------------------------------------------------------
# Shared read-only probes. status.sh and selftest.sh both use these, so the two
# cannot disagree about the lab's success condition.

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# --- the collector's side --------------------------------------------------

# How many tunnel queries reached the collector from <src> in the last <n>
# seconds. The comparison is over a window, so awk does it rather than tail.
tunnel_hits_since() {   # <src-ip> <seconds>
    local now; now="$( date +%s )"
    docker exec "$COLLECTOR_CTN" awk -v ip="$1" -v t="$(( now - $2 ))" \
        '$1 + 0 >= t && $2 == ip { c++ } END { print c + 0 }' "$TUNNEL_LOG" 2>/dev/null || echo 0
}

# Total tunnel queries the collector has logged from <src>, over the whole run.
tunnel_hits_total() {   # <src-ip>
    docker exec "$COLLECTOR_CTN" awk -v ip="$1" \
        '$2 == ip { c++ } END { print c + 0 }' "$TUNNEL_LOG" 2>/dev/null || echo 0
}

# The number of bytes the collector has reassembled from <src>, which is the
# headline oracle: non-zero means the file is leaving, zero means it is not.
tunnel_bytes_from() {   # <src-ip>
    docker exec "$COLLECTOR_CTN" sh -c "wc -c < '$TUNNEL_DIR/$1.bin' 2>/dev/null | tr -dc 0-9" 2>/dev/null || echo 0
}

collector_decoder_running() {
    docker exec "$COLLECTOR_CTN" sh -c 'pgrep -f tunnel-decode.py >/dev/null 2>&1'
}

named_running() {   # <container>
    docker exec "$1" sh -c 'pgrep -x named >/dev/null 2>&1'
}

# --- the gateway's side ----------------------------------------------------

nft_ruleset() {
    docker exec "$GW_CTN" nft list ruleset 2>/dev/null | grep -v '^[[:space:]]*$' || true
}

# --- resolution oracles ----------------------------------------------------

# The address the resolver returns for the legitimate name, asked from <role>.
# Empty when the query got no answer. This is what proves the defence left
# ordinary resolution working.
resolves_legit() {   # <role>
    docker exec "$( ctn_of "$1" )" \
        dig +short +time=2 +tries=1 "@${RESOLVER_IP}" "$LEGIT_NAME" A 2>/dev/null \
        | grep -E '^[0-9]+\.' | head -1
}

# Whether a data query still reaches the collector on a given transport. It sends
# one probe with a unique nonce in its name from <from-role> to <server-ip> (the
# collector's address for the direct transport, the resolver's for the via-the-
# resolver transport), then reads the collector's own query log for that nonce.
# "reaches" means the query arrived; "blocked" means it did not, because the
# gateway dropped it or the resolver's response policy rewrote it before it left.
#
# The probe uses the reserved sequence number below, which the decoder logs to
# named's query file but does not fold into any reassembled file, so running
# Status never changes the byte count the file oracle reads. The nonce is fresh
# each call so the resolver cannot answer a repeat probe from its cache and hide
# a channel that is in fact still open.
PROBE_SEQ=999
tunnel_probe_reaches() {   # <from-role> <server-ip>
    local nonce name
    nonce="$( date +%s )$$${RANDOM:-0}"
    name="probe${nonce}.${PROBE_SEQ}.${TUNNEL_LABEL}"
    docker exec "$( ctn_of "$1" )" \
        dig +short +time=2 +tries=1 "@${2}" "$name" A >/dev/null 2>&1 || true
    sleep 1
    if docker exec "$COLLECTOR_CTN" grep -qi "probe${nonce}\." "$TUNNEL_DIR/queries.log" 2>/dev/null
    then echo reaches; else echo blocked; fi
}
