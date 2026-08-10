#!/usr/bin/env bash
# Shared definitions for the source-spoofing / reflection lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, and interface names. Every other script sources it; never hardcode
# any of these in a second place.
#
# Unlike the L2 labs (one flat broadcast domain), this lab is Layer 3: a single
# forwarding router straddles TWO subnets, and the defence (BCP38 source-address
# verification) sits on the router's customer-facing interface. That interface,
# and the source range that is legitimate on it, are the load-bearing facts here.

AS=102
DC=LAB
SW=S1

# ---------------------------------------------------------------------------
# Two subnets, one router between them.
#   customer edge : the attacker's network, behind the router's INGRESS interface
#   core          : the reflectors + victim, on the far side of the router
# Both live inside the AS's 102.0.0.0/8 block, so subnet_config's AS-octet scheme
# still holds and every address is known before a container exists.
CUST_SUBNET="102.0.0.0/24"   # attacker + router (point-to-point, no switch)
CORE_SUBNET="102.1.0.0/24"   # reflectors + victim + router (switched segment)
PREFIXLEN=24

ROUTER_CUST_IP="102.0.0.1"   # router, customer side  (the attacker's default gateway)
ROUTER_CORE_IP="102.1.0.1"   # router, core side      (the core hosts' default gateway)
ATTACKER_IP="102.0.0.10"     # attacker, on the customer edge
VICTIM_IP="102.1.0.20"       # reflection target; the address the attacker forges as source
DNS_IP="102.1.0.53"          # DNS reflector   (mnemonic: port 53)
NTP_IP="102.1.0.123"         # NTP reflector   (mnemonic: port 123)

# ---------------------------------------------------------------------------
# Interface names.
#   Customer point-to-point link (attacker <-> router), no switch:
ATT_IF="${AS}-cust"          # the attacker's only NIC (host-side <AS>-<peer>)
R_CUST_IF="cust"             # router's customer-facing NIC == the BCP38 ingress interface
#   Core switched segment (router + core hosts <-> S1):
R_CORE_IF="core"             # router's core-facing NIC
HOST_IF="${AS}-${SW}"        # each core host's NIC (victim, dns, ntp), named after the switch

# The defence acts HERE: drop traffic arriving on the customer interface whose
# source is not part of the customer subnet. One interface, one permitted range.
INGRESS_IF="$R_CUST_IF"
CUST_SRC_RANGE="$CUST_SUBNET"

# ---------------------------------------------------------------------------
# Reflector specifics.
# The DNS reflector serves one TXT record, reflect.lab (the walkthrough, reflect
# tool, and selftest all use this name); a forged-source query for it makes the
# reply land on the victim. The NTP reflector answers a mode-6 control "readvar",
# which returns its whole variable list — the post-monlist reflection vector, a
# second unrelated service that reflects the same way. Both names are echoed in the
# handout so the learner queries by name.
REFLECT_NAME="reflect.lab"

# The direct-spoofing stage forges a source that belongs on NEITHER lab subnet,
# so verification has to drop it: there is no interface it could legitimately
# arrive on. TEST-NET-3 (203.0.113.0/24, RFC 5737) never appears in real traffic.
SPOOF_SRC="203.0.113.66"

# ---------------------------------------------------------------------------
SWITCH_IMAGE="miniinterneteth/d_switch"

HOST_IMAGE="d_host_reflect"
# Open vSwitch is started explicitly instead of through the image's supervisord
# entrypoint, so that --no-mlockall can be passed. ovs-ctl locks ovs-vswitchd
# into memory by default. Under rootless Docker CAP_IPC_LOCK is confined to the
# user namespace and cannot exceed RLIMIT_MEMLOCK (8 MB on a stock host), so the
# first thread stack past that limit fails to lock and ovs-vswitchd dies with
# "pthread_create failed (Resource temporarily unavailable)". Locking buys this
# lab nothing: a lab switch forwards a handful of packets and never needs its
# pages pinned. Under rootful Docker the resulting datapath is identical.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# Container names follow the platform convention, with L3 marking the lab's layer:
# <AS>_L3_<DC>_<name>. One prefix covers every container (including the switch, an
# L2 device) so status/teardown can select the lab with a single filter.
SW_CTN="${AS}_L3_${DC}_${SW}"
ROUTER_CTN="${AS}_L3_${DC}_router"
ATTACKER_CTN="${AS}_L3_${DC}_attacker"
VICTIM_CTN="${AS}_L3_${DC}_victim"
DNS_CTN="${AS}_L3_${DC}_dns"
NTP_CTN="${AS}_L3_${DC}_ntp"

# Core hosts wired to the switch S1 (each takes HOST_IF). The router attaches to
# S1 too, but through R_CORE_IF; spawn handles it separately.
CORE_HOSTS=(victim dns ntp)

# Every device that gets a starter config, in apply order: the router first so
# forwarding is up before anything crosses it, reflectors before the victim,
# attacker last.
DEVICES=(router dns ntp victim attacker)

ctn_of()     { echo "${AS}_L3_${DC}_$1"; }
sw_port_of() { echo "${AS}-$1"; }

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# only rebuilt when it is missing, which means an edit to image/reflect never
# reaches a machine that built the image once: the container keeps running the
# previous version and the handout describes a tool the learner does not have.
# That is not hypothetical. The image carried the pre-refocus `amplify.lab`
# default for the whole time image/reflect said `reflect.lab`, so the baked tool
# queried a name dnsmasq does not serve and drew 284 bytes of NXDOMAIN where the
# handout promises 716 bytes of TXT record.
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
# no-op here unless image/ has changed. Without this a fresh checkout fails at
# `docker run` on an image that only ever existed because someone built it by hand.
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
