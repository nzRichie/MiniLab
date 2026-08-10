#!/usr/bin/env bash
# Shared definitions for the VLAN-hopping lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, VLAN IDs, subnets,
# container names, IPs, interface names, and OVS port names. Every other script
# sources it; never hardcode any of these in a second place.
#
# Unlike the other L2 labs (one flat broadcast domain on one switch), this lab has
# TWO switches joined by an 802.1Q trunk, because a double-tagged frame only hops
# across a switch boundary: the first switch strips the outer tag on native-VLAN
# egress, the second switch parses the surviving inner tag fresh and delivers it. A
# single OVS bridge never re-parses a frame after stripping one tag, so one bridge
# cannot demonstrate the attack. The trunk's native VLAN and the attacker's access
# VLAN are the load-bearing facts here: the attack works only while they are equal.

AS=103
DC=LAB
SW1=S1               # access switch: the attacker hangs off this one
SW2=S2               # the switch that holds the victim's VLAN

# ---------------------------------------------------------------------------
# Two VLANs, two subnets. The VLAN id is echoed in the second octet as a mnemonic,
# so every address names its VLAN and a script knows it before a container exists.
VLAN_ATT=10          # the attacker's (and the benign peer's) access VLAN
VLAN_VICTIM=20       # the victim's VLAN; the segment the attacker must not reach

VLAN10_SUBNET="103.10.0.0/24"
VLAN20_SUBNET="103.20.0.0/24"
PREFIXLEN=24

ATTACKER_IP="103.10.0.10"   # attacker, VLAN 10, on S1
PEER_IP="103.10.0.11"       # benign peer, VLAN 10, on S2 (the attacker's honest reach)
VICTIM_IP="103.20.0.20"     # victim, VLAN 20, on S2 (the hop target)

# The forged inner source the attacker writes so the crafted frame looks native to
# VLAN 20. Nothing needs to answer it; the point is that the victim RECEIVES the
# frame. A double-tagged hop is one-way, so no reply returns to VLAN 10 regardless.
SPOOF_SRC="103.20.0.66"

# ---------------------------------------------------------------------------
# The trunk's native VLAN.
#   BAD  = 10: equal to the attacker's access VLAN. This is the misconfiguration
#          that makes double-tagging work: the outer tag (VLAN 10) egresses the
#          trunk UNTAGGED, stripping exactly one tag and exposing the inner VLAN 20.
#   GOOD = 999: an unused parking VLAN no access port carries. Moving the native
#          VLAN here is the "native VLAN off VLAN 1" hardening (generalised: the
#          native VLAN must not equal any access VLAN). With native 999, VLAN 10
#          egresses the trunk TAGGED, so the outer tag is never stripped and the
#          inner tag never surfaces on the far switch.
NATIVE_VLAN_BAD=10
NATIVE_VLAN_GOOD=999

# ---------------------------------------------------------------------------
# Interface names. Each host's NIC is named after the switch it attaches to,
# following the platform's connect_one_l2_host scheme (host side = <AS>-<SW>).
# The attacker is on S1; the peer and victim are on S2.
SW_OF_attacker="$SW1"
SW_OF_peer="$SW2"
SW_OF_victim="$SW2"
sw_of()      { local v="SW_OF_$1"; echo "${!v}"; }          # host -> its switch's short name (S1/S2)
host_if_of() { echo "${AS}-$(sw_of "$1")"; }                # host -> its NIC name (<AS>-<SW>)

SWITCH_IMAGE="miniinterneteth/d_switch"

HOST_IMAGE="d_host_vlan"
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
# Container names follow the platform convention <AS>_L2_<DC>_<name>. Both switches
# share the prefix so status/teardown select the whole lab with one filter.
SW1_CTN="${AS}_L2_${DC}_${SW1}"
SW2_CTN="${AS}_L2_${DC}_${SW2}"
ATTACKER_CTN="${AS}_L2_${DC}_attacker"
PEER_CTN="${AS}_L2_${DC}_peer"
VICTIM_CTN="${AS}_L2_${DC}_victim"

ctn_of() { echo "${AS}_L2_${DC}_$1"; }

# Hosts and the switch each attaches to. spawn wires each host to its switch.
HOSTS=(attacker peer victim)

# Every device that gets a starter config, in apply order: the switches first so
# the VLAN plumbing exists before any host sends a frame, then the hosts.
DEVICES=("$SW1" "$SW2" attacker peer victim)

# ---------------------------------------------------------------------------
# Switch-side OVS port names follow the platform's <AS>-<name> scheme. A trunk port
# is named after the switch on the other end (<AS>-<peer switch>).
#   S1 ports: 103-attacker (access, VLAN 10), 103-S2 (trunk to S2)
#   S2 ports: 103-peer (access, VLAN 10), 103-victim (access, VLAN 20), 103-S1 (trunk to S1)
sw_port_of() { echo "${AS}-$1"; }         # host-facing access port
ATT_PORT="${AS}-attacker"                 # attacker's port on S1 (the lax one)
PEER_PORT="${AS}-peer"                    # peer's port on S2
VICTIM_PORT="${AS}-victim"                # victim's port on S2
S1_TRUNK_PORT="${AS}-${SW2}"              # S1's port toward S2 (the trunk)
S2_TRUNK_PORT="${AS}-${SW1}"              # S2's port toward S1 (the trunk)

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# Image preflight, called by spawn.sh before the first `docker run`.
# The switch image is upstream and pulled; the host image is this lab's own and
# built from image/. Docker caches both, so every spawn after the first is a
# no-op here. Without this a fresh checkout fails at `docker run` on an image
# that only ever existed because someone built it by hand.
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
# True when anything in <dir> is newer than the image built from it. Without this
# check an image is rebuilt only when it is missing, so an edit to image/ never
# reaches a machine that built the image once: the containers keep running the
# previous version while the handout describes the new one. Returns non-zero (no
# rebuild) when the timestamps cannot be read, so a non-GNU `date` or `find`
# degrades to the old behaviour rather than rebuilding on every spawn.
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

# Start the helper and wait until it can run a command. `--rm` plus a bounded
# sleep means an interrupted spawn cannot leave it running forever; spawn also
# stops it explicitly through an EXIT trap.
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
