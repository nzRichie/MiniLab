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
