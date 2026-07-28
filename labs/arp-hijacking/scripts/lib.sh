#!/usr/bin/env bash
# Shared definitions for the ARP-hijacking lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown. No side effects.

AS=100
DC=LAB
SW=S1

SUBNET="100.0.0.0/24"
GW_IP="100.0.0.1"
VICTIM_IP="100.0.0.20"
ATTACKER_IP="100.0.0.10"

# Every host's NIC is named after the switch it attaches to, exactly like the
# platform's connect_one_l2_host primitive (host side = <AS>-<SW>).
HOST_IF="${AS}-${SW}"

SWITCH_IMAGE="miniinterneteth/d_switch"
HOST_IMAGE="d_host_arp"

# Container names follow the platform convention <AS>_L2_<DC>_<name>.
SW_CTN="${AS}_L2_${DC}_${SW}"
ATTACKER_CTN="${AS}_L2_${DC}_attacker"
VICTIM_CTN="${AS}_L2_${DC}_victim"
GATEWAY_CTN="${AS}_L2_${DC}_gateway"

HOSTS=(attacker victim gateway)

ctn_of() { echo "${AS}_L2_${DC}_$1"; }

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
# Wiring a lab needs three privileges a learner's account will not have:
# CAP_NET_ADMIN to create a veth pair in the host's network namespace,
# CAP_SYS_ADMIN to setns into a container and rename the interface there, and
# write access to /run/netns. Rather than require root on the host, a throwaway
# container holds them. --network=host puts it IN the host network namespace, so
# `ip link add` creates the veth exactly where a host-run command would, and
# --pid=host makes each lab container's /proc/<pid>/ns/net reachable for the
# namespace moves.
#
# The kernel objects are identical to the host-root path: same veth pair, same
# namespaces, same interface names, same OVS ports. Only the identity of the
# process issuing the netlink calls changes, which nothing in the data plane can
# observe. Docker group membership becomes the only privilege a learner needs.
#
# The netns symlinks are created inside the helper, so the host's /run/netns is
# never created and teardown has nothing to clean up there.
HELPER_CTN="$( ctn_of netadmin )"

# Start the helper and wait until it can run a command. `--rm` plus a bounded
# sleep means an interrupted spawn cannot leave it running forever; spawn also
# stops it explicitly through an EXIT trap.
helper_start() {
    docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true
    docker run -d --rm --name "$HELPER_CTN" \
        --privileged --network=host --pid=host \
        "$HOST_IMAGE" sleep 600 >/dev/null
    for _ in $(seq 1 40); do
        if docker exec "$HELPER_CTN" true >/dev/null 2>&1; then
            docker exec "$HELPER_CTN" mkdir -p /var/run/netns
            return 0
        fi
        sleep 0.25
    done
    echo "helper container $HELPER_CTN did not become ready" >&2
    return 1
}

# Run one privileged networking command inside the helper.
helper() { docker exec "$HELPER_CTN" "$@"; }

# Make a container's network namespace addressable as `ip netns` name <pid>
# from inside the helper.
helper_bind_netns() {
    docker exec "$HELPER_CTN" ln -sf "/proc/$1/ns/net" "/var/run/netns/$1"
}

helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }
