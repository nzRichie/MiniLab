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
