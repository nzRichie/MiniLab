#!/usr/bin/env bash
# Shared definitions for the DHCP-starvation / rogue-DHCP lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, container names,
# IPs, interface names, and DHCP pools. Every other script sources it; never
# hardcode any of these in a second place.

AS=101
DC=LAB
SW=S1

SUBNET="101.0.0.0/24"
NETMASK="255.255.255.0"

# The legitimate server is also the default gateway it hands out. The attacker's
# own address doubles as the rogue gateway the rogue server hands out.
SERVER_IP="101.0.0.1"
ATTACKER_IP="101.0.0.66"

# The victim has no fixed IP: it leases one over DHCP (that is the whole point).
# These bound the two pools so a script knows every address before a lease exists.
LEGIT_POOL_LO="101.0.0.100"
LEGIT_POOL_HI="101.0.0.120"
ROGUE_POOL_LO="101.0.0.150"
ROGUE_POOL_HI="101.0.0.200"

# An address off this subnet, used to prove the on-path position: the victim sends
# it to whatever it believes is the default gateway, so a poisoned lease routes it
# to the attacker. Nothing on the isolated bridge answers it; the point is who
# RECEIVES it.
OFFSUBNET_IP="101.0.1.1"

# Every host's NIC is named after the switch it attaches to, exactly like the
# platform's connect_one_l2_host primitive (host side = <AS>-<SW>).
HOST_IF="${AS}-${SW}"

SWITCH_IMAGE="miniinterneteth/d_switch"

HOST_IMAGE="d_host_dhcp"
# Open vSwitch is started explicitly instead of through the image's supervisord
# entrypoint, so that --no-mlockall can be passed. ovs-ctl locks ovs-vswitchd
# into memory by default. Under rootless Docker CAP_IPC_LOCK is confined to the
# user namespace and cannot exceed RLIMIT_MEMLOCK (8 MB on a stock host), so the
# first thread stack past that limit fails to lock and ovs-vswitchd dies with
# "pthread_create failed (Resource temporarily unavailable)". Locking buys this
# lab nothing: a lab switch forwards a handful of packets and never needs its
# pages pinned. Under rootful Docker the resulting datapath is identical.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# Container names follow the platform convention <AS>_L2_<DC>_<name>.
SW_CTN="${AS}_L2_${DC}_${SW}"
SERVER_CTN="${AS}_L2_${DC}_server"
VICTIM_CTN="${AS}_L2_${DC}_victim"
ATTACKER_CTN="${AS}_L2_${DC}_attacker"

# Order matters for spawn/reset: the server's dhcpd must be serving before the
# victim runs its client, so `server` is configured first and `victim` last.
HOSTS=(server attacker victim)

# Switch-side OVS port names follow the platform's <AS>-<name> scheme. The server
# port is the ONE trusted port for DHCP snooping; the rest are access ports.
TRUSTED_PORT="${AS}-server"
ACCESS_PORTS=("${AS}-victim" "${AS}-attacker")

ctn_of()     { echo "${AS}_L2_${DC}_$1"; }
sw_port_of() { echo "${AS}-$1"; }

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
