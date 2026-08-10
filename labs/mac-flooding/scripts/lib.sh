#!/usr/bin/env bash
# Shared definitions for the MAC-flooding lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnet, container
# names, IPs, interface names, OVS port names and the MAC-table size. Every other
# script sources it; never hardcode any of these in a second place.
#
# TWO switches, and an uplink that carries more MAC addresses than any access
# port, and that is the whole lab. Open vSwitch does not evict from its MAC table
# in plain least-recently-used order: when the table is full it evicts from the
# port currently holding the MOST entries, "so that there is a degree of fairness,
# that is, each port is entitled to its fair share of MAC entries"
# (lib/mac-learning.c, evict_mac_entry_fairly). On one switch with one host per
# port, a flooding attacker is always the largest holder, so it only ever evicts
# its own entries: measured here at 505,637 evictions with the victim's entry
# untouched throughout, and not one frame leaked. The classic textbook attack does
# not work on this switch.
#
# What fair eviction does not protect is a port carrying more than its share. S1's
# uplink holds the MAC of every device beyond it (the gateway plus ten staff
# machines, 11 addresses), which is more than the 8 a two-way split of a 16-entry
# table leaves it. So the flood squeezes the uplink down to its share, the least
# recently used entry on that port goes first, and the gateway - quiet between the
# victim's pings, while the staff machines chatter - is the one that goes.
#
#      S1 (access, mac-table-size=16)          S2 (distribution)
#        victim   --+                            +-- gateway 106.0.0.1
#        attacker --+--- uplink ========= uplink-+-- staff x10 (106.0.0.31-.40)

AS=106
DC=LAB
SW1=S1               # the access switch: victim and attacker hang off it
SW2=S2               # the distribution switch: gateway and the staff machines

# ---------------------------------------------------------------------------
# One flat broadcast domain across both switches. Addresses are fixed so the
# handout can name them and a script knows every one before a container exists.
SUBNET="106.0.0.0/24"
PREFIXLEN=24

GATEWAY_IP="106.0.0.1"      # behind S2; what the victim talks to, and the target
ATTACKER_IP="106.0.0.10"    # on S1, an ordinary access port
VICTIM_IP="106.0.0.20"      # on S1, an ordinary access port

# The ten staff machines behind the uplink, 106.0.0.31 .. 106.0.0.40. They are why
# S1's uplink port carries eleven addresses instead of one, which is the only
# reason this attack has anything to bite on. Each is a real interface with its
# own MAC and address in the staff container, wired to its own port on S2, so
# `ovs-appctl fdb/show` on S1 shows eleven genuine entries on the uplink and the
# learner can ping any of them.
STAFF_COUNT=10
STAFF_IP_BASE=30            # staff N is 106.0.0.$((STAFF_IP_BASE + N))
staff_ip()   { echo "106.0.0.$(( STAFF_IP_BASE + $1 ))"; }
staff_name() { printf 'staff%02d' "$1"; }

# ---------------------------------------------------------------------------
# The MAC table. 16 is small on purpose: a real access switch holds 8,000 to
# 128,000 entries and would take a flood minutes to fill, while 16 fills in
# milliseconds and makes every measurement in this lab repeatable on a laptop.
# The arithmetic the lab turns on:
#
#   baseline    11 (uplink) + 1 (victim) + 1 (attacker) = 13 of 16, no eviction
#   under flood 16 of 16, and the two largest ports settle at roughly 8 and 7,
#               so the uplink loses about four of its eleven addresses
#
# ovs-vswitchd clamps this value to at least 10 (mac_learning_set_max_entries in
# lib/mac-learning.c), so a smaller number here would be silently ignored rather
# than applied.
MAC_TABLE_SIZE=16
MAC_TABLE_MIN=10            # the daemon's floor; anything lower is clamped up

# S2 keeps the stock table size. The attack is aimed at S1, and leaving S2 at its
# default is what lets the learner see that the same flood crossing the same
# uplink does nothing to a switch with room to absorb it.
S2_MAC_TABLE_SIZE=2048

# ---------------------------------------------------------------------------
# Interface names. A host NIC is named after the switch it attaches to
# (host side = <AS>-<SW>), following the platform's connect_one_l2_host scheme.
# The staff container is the one device with more than one NIC, so its interfaces
# carry an index: 106-S2-01 .. 106-S2-10.
VICTIM_IF="${AS}-${SW1}"
ATTACKER_IF="${AS}-${SW1}"
GATEWAY_IF="${AS}-${SW2}"
staff_if() { printf '%s-%s-%02d' "$AS" "$SW2" "$1"; }

# The uplink. Each end is named after the switch on the other side, exactly like
# the inter-switch links in the other multi-switch labs.
S1_UPLINK_PORT="${AS}-${SW2}"    # on S1, facing S2
S2_UPLINK_PORT="${AS}-${SW1}"    # on S2, facing S1

# Switch-side OVS port names follow the platform's <AS>-<name> scheme.
sw_port_of()   { echo "${AS}-$1"; }
VICTIM_PORT="${AS}-victim"       # on S1
ATTACKER_PORT="${AS}-attacker"   # on S1: the access port the flood arrives on
GATEWAY_PORT="${AS}-gateway"     # on S2
staff_port()   { printf '%s-staff%02d' "$AS" "$1"; }

SWITCH_IMAGE="miniinterneteth/d_switch"

HOST_IMAGE="d_host_macflood"
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
# Container names follow the platform convention <AS>_L2_<DC>_<name>. All six
# share the prefix so status/teardown select the whole lab with one filter.
SW1_CTN="${AS}_L2_${DC}_${SW1}"
SW2_CTN="${AS}_L2_${DC}_${SW2}"
ATTACKER_CTN="${AS}_L2_${DC}_attacker"
VICTIM_CTN="${AS}_L2_${DC}_victim"
GATEWAY_CTN="${AS}_L2_${DC}_gateway"
STAFF_CTN="${AS}_L2_${DC}_staff"

ctn_of() { echo "${AS}_L2_${DC}_$1"; }

SWITCHES=("$SW1" "$SW2")
HOSTS=(attacker victim gateway staff)

# Every device that gets a starter config, in apply order: the switches first so
# the MAC table is sized before a host sends a frame, then the hosts, with staff
# last because its keepalive traffic is what fills the uplink's share of the table.
DEVICES=("$SW1" "$SW2" attacker victim gateway staff)

# The access port the port-security defence is applied to. Only the attacker's:
# the defence is per-port and the lab is about closing the port the flood arrives
# on, not about locking down the whole switch.
GUARDED_PORTS=("$SW1_CTN $ATTACKER_PORT")

# ---------------------------------------------------------------------------
# The two defences, as OpenFlow priorities, so status/reset/selftest all recognise
# the learner's work by the same numbers the handout tells them to type.
#
# PIN_PRIORITY   a static forwarding entry: frames addressed to the gateway leave
#                by the uplink because the flow table says so, with no lookup in
#                the learning table at all. Survives a full table.
# SECURE_PRIORITY / DROP_PRIORITY
#                port security: the one source address the attacker's access port
#                is allowed to use is forwarded normally, everything else on that
#                port is dropped before it can be learned from.
PIN_PRIORITY=200
SECURE_PRIORITY=300
DROP_PRIORITY=100

# `ovs-appctl fdb/add` is NOT one of the defences, and the handout says why. It
# adds an entry flagged static, which is exempt from AGEING but not from
# EVICTION: evict_mac_entry_fairly takes the least recently used entry on the
# busiest port and has no static check (lib/mac-learning.c). Nothing ever
# refreshes a static entry, so it sits permanently at the front of its port's LRU
# list and is the FIRST thing a flood takes. Measured: pinned at baseline, gone
# within three seconds of the flood starting, and 10 of 10 frames leaked.

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# The lab's oracles. Every stage asks the same three questions of the switch:
# how full is the table, which port is holding what, and is the gateway's entry
# still there.

# The MAC address a host currently has on the interface facing its switch.
mac_of() {   # <container> <interface>
    docker exec "$1" cat "/sys/class/net/$2/address" 2>/dev/null | tr -d '\r\n'
}
gateway_mac()  { mac_of "$GATEWAY_CTN"  "$GATEWAY_IF";  }
victim_mac()   { mac_of "$VICTIM_CTN"   "$VICTIM_IF";   }
attacker_mac() { mac_of "$ATTACKER_CTN" "$ATTACKER_IF"; }

# The OpenFlow port number OVS gave a named port. The flow rules the learner
# writes match on in_port, which takes the number, not the name.
of_port_of() {   # <switch container> <port name>
    docker exec "$1" ovs-ofctl show br0 2>/dev/null \
        | awk -F'[( ]+' -v p="$2" '$0 ~ "\\(" p "\\)" { print $2; exit }'
}

# "<current>/<max>" from fdb/stats-show: how full the table is right now.
fdb_fill() {   # <switch container> -> "<current> <max>"
    docker exec "$1" ovs-appctl fdb/stats-show br0 2>/dev/null \
        | awk -F: '/Current\/maximum MAC entries/ { gsub(/[ \t]/, "", $2); split($2, a, "/"); print a[1], a[2] }'
}

# How many entries a given OVS port is holding in the MAC table. This is the
# number fair eviction acts on: the port with the largest count is the one the
# next eviction takes an entry from.
fdb_entries_on_port() {   # <switch container> <port name> -> count
    local n
    n="$( of_port_of "$1" "$2" )"
    [ -n "$n" ] || { echo 0; return; }
    docker exec "$1" ovs-appctl fdb/show br0 2>/dev/null \
        | awk -v p="$n" 'NR > 1 && $1 == p' | wc -l | tr -d ' '
}

# Running eviction count, which is how the lab shows the table is thrashing even
# when nothing has leaked yet.
fdb_evicted() {   # <switch container> -> count
    docker exec "$1" ovs-appctl fdb/stats-show br0 2>/dev/null \
        | awk -F: '/Total number of evicted/ { gsub(/[ \t]/, "", $2); print $2 }'
}

# Is a MAC in the table at all, and is its entry static? A static entry (added
# with `ovs-appctl fdb/add`) prints "static" in the Age column and is exempt from
# both ageing and eviction, which is the second defence in Part 2.
fdb_has_mac()    { docker exec "$1" ovs-appctl fdb/show br0 2>/dev/null | grep -qi "$2"; }
fdb_mac_static() { docker exec "$1" ovs-appctl fdb/show br0 2>/dev/null | grep -i "$2" | grep -q 'static'; }

# ---------------------------------------------------------------------------
# The interception oracle: how many victim-to-gateway frames reach the attacker's
# access port. A frame is only there because S1 had no table entry for the
# gateway's MAC and flooded it to every port, so the count answers exactly the
# question the lab asks. The filter is on the DESTINATION address: traffic
# addressed to the attacker itself is not interception and must not be counted.
#
# Judged against a threshold rather than against zero. The victim's very first
# exchange after any table change is flooded regardless of the attack, so a single
# stray frame is not a leak; a flood held open across ten echo requests produces
# one leaked frame per request. Measured: 0 to 1 frames with the table intact,
# 9 to 10 with the gateway's entry being evicted. The line goes at 5, the midpoint.
LEAK_PROBES=10
LEAK_MIN=5
leaking()     { [ "${1:-0}" -ge "$LEAK_MIN" ]; }
not_leaking() { [ "${1:-0}" -lt "$LEAK_MIN" ]; }

# Count victim-to-gateway frames arriving on the attacker's access port while the
# victim sends LEAK_PROBES echo requests, and the gateway's replies to the victim
# in the SAME window. Both filters are on the destination address, so the pair is
# exactly what Question 8 asks about: the forward direction leaks because the
# gateway's row has been evicted, and the reverse does not, because the victim's
# row sits on a port fair eviction never takes from. Measuring both in one ping
# run is what makes the reverse count comparable with the forward one; measuring
# them in separate runs would compare two different states of the table.
attacker_sees_both() {   # -> "<victim-to-gateway> <gateway-to-victim>"
    local gmac vmac fwd rev
    gmac="$( gateway_mac )"
    vmac="$( victim_mac )"
    docker exec "$ATTACKER_CTN" sh -c 'rm -f /tmp/leak.pcap /tmp/leak-rev.pcap' 2>/dev/null
    docker exec -d "$ATTACKER_CTN" sh -c \
        "timeout 20 tcpdump -n -i $ATTACKER_IF -w /tmp/leak.pcap 'ether dst $gmac and icmp' >/dev/null 2>&1"
    docker exec -d "$ATTACKER_CTN" sh -c \
        "timeout 20 tcpdump -n -i $ATTACKER_IF -w /tmp/leak-rev.pcap 'ether dst $vmac and icmp' >/dev/null 2>&1"
    sleep 1
    docker exec "$VICTIM_CTN" ping -c"$LEAK_PROBES" -i 0.5 -W1 "$GATEWAY_IP" >/dev/null 2>&1 || true
    sleep 1
    docker exec "$ATTACKER_CTN" pkill -f tcpdump >/dev/null 2>&1 || true
    sleep 0.4
    fwd="$( docker exec "$ATTACKER_CTN" sh -c 'tcpdump -nr /tmp/leak.pcap 2>/dev/null | wc -l' | tr -d ' \r\n' )"
    rev="$( docker exec "$ATTACKER_CTN" sh -c 'tcpdump -nr /tmp/leak-rev.pcap 2>/dev/null | wc -l' | tr -d ' \r\n' )"
    echo "${fwd:-0} ${rev:-0}"
}

attacker_sees() {   # -> frame count, forward direction only
    local fwd rev
    read -r fwd rev <<<"$( attacker_sees_both )"
    echo "${fwd:-0}"
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
