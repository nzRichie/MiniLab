#!/usr/bin/env bash
# Shared definitions for the STP root-bridge-takeover lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnet, container
# names, IPs, interface names, OVS port names and bridge priorities. Every other
# script sources it; never hardcode any of these in a second place.
#
# THREE switches in a ring, not two, and the reason is the whole lab. A spanning
# tree only has something to decide when the physical topology contains a loop, so
# a ring is the smallest honest baseline: STP elects a root and blocks exactly one
# port to break the loop. It also decides whether the attack has any effect at all.
# On a two-switch topology with the attacker hanging off one of them, winning the
# root election changes NO forwarding path (measured: zero packets lost, because
# the relative order of the two switches on the way to the root is the same before
# and after). In a ring, a takeover moves which port blocks, so it costs real
# connectivity. See VERIFIED-FACTS.md in this lab for the measurements.
#
#            S1  (intended root, priority 4096)
#           /  \
#         S2 -- S3          <- the S2-S3 link is the one STP blocks at baseline
#         |      |
#      victim  gateway
#         \      /
#          attacker         <- link A to S2 is up; link B to S3 is down until Part 2

AS=105
DC=LAB
SW1=S1               # the intended root: lowest configured priority
SW2=S2               # holds the victim and the attacker's first link
SW3=S3               # holds the gateway and the attacker's second link

# ---------------------------------------------------------------------------
# One flat broadcast domain across all three switches. Addresses are fixed so the
# handout can name them and a script knows every one before a container exists.
SUBNET="105.0.0.0/24"
PREFIXLEN=24

GATEWAY_IP="105.0.0.1"      # the gateway, behind S3; what the victim talks to
ATTACKER_IP="105.0.0.10"    # the attacker, on S2 (and on S3 once link B is up)
VICTIM_IP="105.0.0.20"      # the victim, behind S2

# ---------------------------------------------------------------------------
# Bridge priorities. 802.1D compares the 8-byte bridge ID (2-byte priority then
# the 6-byte MAC) and the NUMERICALLY LOWEST wins, so the priority is the only
# part an administrator controls. OVS takes it as other_config:stp-priority and
# accepts any value the 16-bit field can hold: `stp-priority=100` was tested and
# is reported back verbatim by `ovs-appctl stp/show`. The multiple-of-4096 rule
# people expect here comes from the 4-bit-priority-plus-system-ID-extension format
# that RSTP and MSTP use, which this 802.1D-1998 implementation does not. The
# values below are spaced by 4096 out of convention, not necessity.
#
# S1 is given the lowest, so the intended tree is rooted at S1 and the blocked
# port lands on the S2-S3 link. The attacker beats all three by claiming 0, which
# no legitimate bridge here uses.
PRIO_SW1=4096
PRIO_SW2=8192
PRIO_SW3=12288

# The bridge ID the attacker forges. Priority 0 is the lowest value the field can
# hold, so this claim wins the election outright regardless of any MAC tie-break.
# The MAC is a fixed, obviously-synthetic value rather than the attacker's own, so
# that a learner reading `ovs-appctl stp/show` can tell at a glance that the root
# the switches now believe in is not any bridge in the diagram.
FORGED_PRIO=0
FORGED_MAC="00:11:22:33:44:55"

# 802.1D default timers, which this lab leaves at their defaults on purpose: the
# time they cost is the point (a port moving from blocking to forwarding waits out
# listening AND learning, one forward delay each). The handout has the learner
# measure the outage rather than read it from here.
HELLO_TIME=2
MAX_AGE=20
FORWARD_DELAY=15

# ---------------------------------------------------------------------------
# Interface names. Each host NIC is named after the switch it attaches to
# (host side = <AS>-<SW>), following the platform's connect_one_l2_host scheme.
# The attacker is the only device with two, which is what Part 2 turns on.
VICTIM_IF="${AS}-${SW2}"        # victim  -> S2
GATEWAY_IF="${AS}-${SW3}"       # gateway -> S3
ATTACKER_IF_A="${AS}-${SW2}"    # attacker -> S2   (up from spawn)
ATTACKER_IF_B="${AS}-${SW3}"    # attacker -> S3   (DOWN until the learner raises it)

# The bridge the attacker builds across its two NICs in Part 2. Its STP must stay
# off: a Linux bridge with stp_state=0 forwards the BPDUs it receives rather than
# consuming them, which is what stops the second link from creating a loop the
# switches cannot see. (Kernel br_handle_frame: a BPDU is forwarded when the
# bridge's own STP is off, "to keep loop detection" working in the wider network.)
ATTACKER_BRIDGE="br0"

SWITCH_IMAGE="miniinterneteth/d_switch"

HOST_IMAGE="d_host_stp"
# Open vSwitch is started explicitly instead of through the image's supervisord
# entrypoint, so that --no-mlockall can be passed. ovs-ctl locks ovs-vswitchd
# into memory by default. Under rootless Docker CAP_IPC_LOCK is confined to the
# user namespace and cannot exceed RLIMIT_MEMLOCK (8 MB on a stock host), so the
# first thread stack past that limit fails to lock and ovs-vswitchd dies with
# "pthread_create failed (Resource temporarily unavailable)". Locking buys this
# lab nothing: a lab switch forwards a handful of packets and never needs its
# pages pinned. Under rootful Docker the resulting datapath is identical.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# Container names follow the platform convention <AS>_L2_<DC>_<name>. All five
# share the prefix so status/teardown select the whole lab with one filter.
SW1_CTN="${AS}_L2_${DC}_${SW1}"
SW2_CTN="${AS}_L2_${DC}_${SW2}"
SW3_CTN="${AS}_L2_${DC}_${SW3}"
ATTACKER_CTN="${AS}_L2_${DC}_attacker"
VICTIM_CTN="${AS}_L2_${DC}_victim"
GATEWAY_CTN="${AS}_L2_${DC}_gateway"

ctn_of() { echo "${AS}_L2_${DC}_$1"; }

SWITCHES=("$SW1" "$SW2" "$SW3")
HOSTS=(attacker victim gateway)

# Every device that gets a starter config, in apply order: the switches first so
# STP is running before a host sends a frame, then the hosts.
DEVICES=("$SW1" "$SW2" "$SW3" attacker victim gateway)

# ---------------------------------------------------------------------------
# Switch-side OVS port names follow the platform's <AS>-<name> scheme: a
# host-facing port is named after the host, an inter-switch port after the switch
# on the other end.
#   S1: 105-S2, 105-S3
#   S2: 105-S1, 105-S3, 105-victim, 105-attacker
#   S3: 105-S1, 105-S2, 105-gateway, 105-attacker
sw_port_of()  { echo "${AS}-$1"; }
VICTIM_PORT="${AS}-victim"       # on S2
GATEWAY_PORT="${AS}-gateway"     # on S3
ATT_PORT_S2="${AS}-attacker"     # attacker's port on S2: an access port, and lax
ATT_PORT_S3="${AS}-attacker"     # attacker's port on S3: the same, on the far switch

# The two access ports the defence is applied to, as "<container> <port>" pairs.
# Both, not one: Part 2's attacker claims the root out of both of its NICs, so a
# guard on a single switch leaves the other switch still believing the forgery.
ACCESS_PORTS=("$SW2_CTN $ATT_PORT_S2" "$SW3_CTN $ATT_PORT_S3")

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# Read the bridge ID a switch currently believes is the root, as printed by
# `ovs-appctl stp/show`. Returns "<priority> <mac>". This is the lab's oracle:
# every stage asks who the root is and whether the answer is a real bridge.
stp_root_of() {   # <switch container> -> "<priority> <mac>"
    docker exec "$1" ovs-appctl stp/show 2>/dev/null | awk '
        /^Root ID:/     { in_root = 1; next }
        /^Bridge ID:/   { in_root = 0 }
        in_root && /stp-priority/  { prio = $2 }
        in_root && /stp-system-id/ { mac  = $2 }
        END { print prio, mac }'
}

# The role and state of one port, as "<role> <state>" (e.g. "alternate blocking").
# A port excluded from STP is not listed at all, and prints "absent absent".
stp_port_state() {   # <switch container> <port> -> "<role> <state>"
    docker exec "$1" ovs-appctl stp/show 2>/dev/null \
        | awk -v p="$2" '$1 == substr(p, 1, length($1)) && NF >= 5 && $1 ~ /^'"${AS}"'-/ {
              if (index(p, $1) == 1) { print $2, $3; found = 1; exit }
          }
          END { if (!found) print "absent absent" }'
}

# True when the switch names a bridge OTHER than one of the lab's own three as
# root: that is exactly what a successful takeover looks like from the switch.
stp_root_is_forged() {   # <switch container>
    local root; root="$( stp_root_of "$1" )"
    [ "${root%% *}" = "$FORGED_PRIO" ]
}

# ---------------------------------------------------------------------------
# Image preflight, called by spawn.sh before the first `docker run`. The switch
# image is upstream and pulled; the host image is this lab's own and built from
# image/. Docker caches both, so every spawn after the first is a no-op here.
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

# True when anything in <dir> is newer than the image built from it. Without this
# an image is rebuilt only when it is missing, so an edit to image/ never reaches
# a machine that built the image once. Returns non-zero (no rebuild) when the
# timestamps cannot be read, so a non-GNU `date` or `find` degrades to the old
# behaviour rather than rebuilding on every spawn.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
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
#
# The kernel objects are identical to the host-root path: same veth pair, same
# namespaces, same interface names, same OVS ports. Only the identity of the
# process issuing the netlink calls changes, which nothing in the data plane can
# observe. Docker access is the only privilege a learner needs, and on a rootless
# daemon that access no longer carries root on the host.
HELPER_CTN="$( ctn_of netadmin )"

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
