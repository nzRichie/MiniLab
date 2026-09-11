#!/usr/bin/env bash
# Shared definitions for the addressing-and-static-routing lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, interface names and every address the reference solution assigns. Every
# other script sources it; never hardcode any of these in a second place.
#
# The lab is Layer 3 and it is a configuration exercise, not an attack. What the
# learner is handed is eleven containers wired into three subnets with not one
# address configured and every lab-facing interface administratively down. What
# they build is the addressing, the host default routes, and the two static
# routes on the routers that turn six isolated segments into one reachable
# network.

AS=108
DC=LAB

# ---------------------------------------------------------------------------
# Three subnets, two routers, six hosts, three switches.
#
#   west-1 --+                          +-- mid-1        +-- east-1
#            +-- S-WEST -- west-router --+-- S-MID -- east-router -- S-EAST --+
#   west-2 --+                          +-- mid-2        +-- east-2
#
# West Net and East Net are stub segments: each has exactly one router on it, so
# a host there has exactly one way off its own subnet. Middle Net has both
# routers on it, so a host there has two candidate default gateways and only one
# of them is the shorter path to any given far subnet. That asymmetry is what the
# lab's last section is about.
#
# The addresses are RFC 1918 private space rather than this catalogue's usual
# AS-octet scheme (100.0.0.0/24 in arp-hijacking, 107.1.0.0/24 in dns-poisoning).
# Nothing routes between this lab and any other, so the AS octet buys nothing
# here, and 192.168.1/2/3.0/24 is the address space a learner meets on every
# home and campus network they will configure after this one.
WEST_SUBNET="192.168.1.0/24"
MID_SUBNET="192.168.2.0/24"
EAST_SUBNET="192.168.3.0/24"
PREFIXLEN=24

# Hosts take .11 and .12 on their own subnet; routers take low addresses. Every
# one of these is a value the learner types by hand, and the handout's addressing
# table is generated from the same list status.sh checks against.
IP_WEST1="192.168.1.11"
IP_WEST2="192.168.1.12"
IP_WR_WEST="192.168.1.1"      # west-router, West Net side
IP_WR_MID="192.168.2.2"       # west-router, Middle Net side
IP_ER_MID="192.168.2.1"       # east-router, Middle Net side
IP_MID1="192.168.2.11"
IP_MID2="192.168.2.12"
IP_ER_EAST="192.168.3.1"      # east-router, East Net side
IP_EAST1="192.168.3.11"
IP_EAST2="192.168.3.12"

# ---------------------------------------------------------------------------
# Interface names. A device's lab-facing NIC is named after the subnet it sits
# on, not after the switch, because a router has one interface on each of two
# subnets and needs to tell them apart by sight. A router therefore holds both
# 108-WEST and 108-MID, or both 108-MID and 108-EAST.
WEST_IF="${AS}-WEST"
MID_IF="${AS}-MID"
EAST_IF="${AS}-EAST"

# ---------------------------------------------------------------------------
SW_WEST="S-WEST"
SW_MID="S-MID"
SW_EAST="S-EAST"
SWITCHES=("$SW_WEST" "$SW_MID" "$SW_EAST")

# The six hosts, and the two routers, kept apart because they differ in three
# ways: a router is started with net.ipv4.ip_forward=1, holds two interfaces
# instead of one, and gets static routes rather than a default route.
HOSTS=(west-1 west-2 mid-1 mid-2 east-1 east-2)
ROUTERS=(west-router east-router)
DEVICES=("${HOSTS[@]}" "${ROUTERS[@]}")

# ---------------------------------------------------------------------------
# The wiring table: one row per interface, which is one row per link, because
# every link in this lab runs from a device to a switch. Ten rows, which is the
# ten interfaces the handout has the learner address.
#
#   <device> <interface> <switch> <address the reference solution assigns>
LINKS=(
    "west-1      ${WEST_IF} ${SW_WEST} ${IP_WEST1}"
    "west-2      ${WEST_IF} ${SW_WEST} ${IP_WEST2}"
    "west-router ${WEST_IF} ${SW_WEST} ${IP_WR_WEST}"
    "west-router ${MID_IF}  ${SW_MID}  ${IP_WR_MID}"
    "east-router ${MID_IF}  ${SW_MID}  ${IP_ER_MID}"
    "mid-1       ${MID_IF}  ${SW_MID}  ${IP_MID1}"
    "mid-2       ${MID_IF}  ${SW_MID}  ${IP_MID2}"
    "east-router ${EAST_IF} ${SW_EAST} ${IP_ER_EAST}"
    "east-1      ${EAST_IF} ${SW_EAST} ${IP_EAST1}"
    "east-2      ${EAST_IF} ${SW_EAST} ${IP_EAST2}"
)

# Each host's own address and the interface it goes on, for the checks that walk
# hosts rather than links.
host_if()   { case "$1" in west-*) echo "$WEST_IF" ;; mid-*) echo "$MID_IF" ;; east-*) echo "$EAST_IF" ;; esac; }
host_ip()   {
    case "$1" in
        west-1) echo "$IP_WEST1" ;; west-2) echo "$IP_WEST2" ;;
        mid-1)  echo "$IP_MID1"  ;; mid-2)  echo "$IP_MID2"  ;;
        east-1) echo "$IP_EAST1" ;; east-2) echo "$IP_EAST2" ;;
    esac
}

# The default gateway the reference solution gives each host.
#
# West Net and East Net hosts have one router on their subnet and therefore one
# possible answer. Middle Net hosts have two, and both are legal: either one
# reaches everything, because whichever router a Middle Net host picks, the other
# router is one hop further on and reachable across the same subnet. The
# reference picks west-router for both, which puts mid-1's path to East Net
# through the router that is NOT its shortest way there. That is deliberate: it
# is what makes the last section's ICMP redirect happen.
DEFAULT_GW_MID="$IP_WR_MID"
default_gw_of() {
    case "$1" in
        west-*) echo "$IP_WR_WEST" ;;
        mid-*)  echo "$DEFAULT_GW_MID" ;;
        east-*) echo "$IP_ER_EAST" ;;
    esac
}

# The two static routes the learner adds, one per router. Nothing else in the
# network needs a route entry that is not either connected or a default.
#   <router> <destination prefix> <next hop>
STATIC_ROUTES=(
    "west-router ${EAST_SUBNET} ${IP_ER_MID}"
    "east-router ${WEST_SUBNET} ${IP_WR_MID}"
)

# ---------------------------------------------------------------------------
SWITCH_IMAGE="miniinterneteth/d_switch"
HOST_IMAGE="d_host_netcfg"

# Open vSwitch is started explicitly instead of through the image's supervisord
# entrypoint, so that --no-mlockall can be passed. ovs-ctl locks ovs-vswitchd
# into memory by default. Under rootless Docker CAP_IPC_LOCK is confined to the
# user namespace and cannot exceed RLIMIT_MEMLOCK (8 MB on a stock host), so the
# first thread stack past that limit fails to lock and ovs-vswitchd dies with
# "pthread_create failed (Resource temporarily unavailable)". Locking buys this
# lab nothing: a lab switch forwards a handful of packets and never needs its
# pages pinned. Under rootful Docker the resulting datapath is identical.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# Container names follow the platform convention: <AS>_<LAYER>_<DC>_<name>. One
# prefix covers every container, including the three switches, so status.sh and
# teardown.sh select the whole lab with a single filter.
ctn_of()     { echo "${AS}_L3_${DC}_$1"; }
sw_port_of() { echo "${AS}-$1"; }

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# Helpers the lifecycle scripts and selftest share, so neither repeats a docker
# incantation the other has to be kept in step with.

# The address currently configured on a device's interface, with its prefix
# length, or nothing when the interface has none.
addr_on() {   # <device> <interface>
    docker exec "$( ctn_of "$1" )" ip -4 -o addr show dev "$2" 2>/dev/null \
        | awk '{ for (i = 1; i <= NF; i++) if ($i == "inet") { print $(i+1); exit } }'
}

# True while the interface is administratively up (state UP or UNKNOWN, which is
# what a veth with no carrier reports before its peer comes up).
if_is_up() {   # <device> <interface>
    docker exec "$( ctn_of "$1" )" ip -o link show dev "$2" 2>/dev/null \
        | grep -q ',UP'
}

# The next hop of a device's default route, or nothing when it has none.
default_route_of() {   # <device>
    docker exec "$( ctn_of "$1" )" ip -4 route show default 2>/dev/null \
        | awk '$1 == "default" { print $3; exit }'
}

# Every route entry the device holds, one per line, as `ip route show` prints it.
routes_of() {   # <device>
    docker exec "$( ctn_of "$1" )" ip -4 route show 2>/dev/null
}

# Two ICMP echo requests, a second of patience each. Exit 0 when either was
# answered. -n keeps ping off name resolution, which nothing in this lab provides.
#
# Two rather than one, because the first packet to a destination whose hardware
# address is not yet in the sender's neighbour table is queued while ARP resolves,
# and on a cold network with thirty of these running at once that resolution has
# been measured to overrun a one-second deadline. A single-packet check then
# reports an unreachable pair on a network that is correctly configured, which is
# the one thing this lab's oracle must never do.
can_ping() {   # <device> <address>
    docker exec "$( ctn_of "$1" )" ping -n -c 2 -i 0.3 -W 1 "$2" >/dev/null 2>&1
}

# What ping prints when it fails, which is the part the handout asks a learner to
# read: "connect: Network unreachable" and "Destination Host Unreachable" come
# from different places and mean different things. Drops the banner line and the
# statistics block, leaving the lines that say what went wrong.
ping_message() {   # <device> <address>
    docker exec "$( ctn_of "$1" )" ping -n -c 1 -W 1 "$2" 2>&1 \
        | grep -vE '^(PING|---|[0-9]+ packets transmitted|rtt |$)' | head -2
}

# The next hop the kernel would use for one destination right now, including any
# cached exception an ICMP redirect installed. `ip route show` does not list
# those; `ip route get` is the only thing that reports them.
next_hop_for() {   # <device> <address>
    docker exec "$( ctn_of "$1" )" ip -4 route get "$2" 2>/dev/null \
        | awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i+1); exit } }'
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
