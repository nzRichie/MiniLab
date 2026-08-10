#!/usr/bin/env bash
# Spawn the honeypot deployment lab: an attacker outside, a router, the
# production host it is after, a decoy, and the management station whose access
# has to survive the defence. Self-contained — drives docker + the veth
# primitives directly, WITHOUT the full platform/startup.sh pipeline (RQ1).
#
# Every segment holds one host, so there is no switch and no OVS anywhere in this
# lab. Four point-to-point veth pairs meet at the router:
#
#   attacker --- router --- prod
#                  |  \
#              honeypot  admin
#
# The router is the only device that sees traffic between two segments, and so
# the only device the learner writes config on.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and can this account reach it? (try: docker info)" >&2
    exit 1
}

if docker ps -a --format '{{.Names}}' | grep -qx "$ROUTER_CTN"; then
    echo "Lab already spawned ($ROUTER_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# The redirect the learner writes in Part 2 is a destination NAT rule, which
# needs the kernel's nat chain type available inside the router's namespace.
# Autoloading a netfilter module needs privilege in the initial namespace, which
# a rootless daemon's containers do not have, so on a host where nothing has ever
# used nat the rule would fail halfway through Part 2 with an error the learner
# has no way to interpret. Fail here instead, with the reason.
log "checking the router's kernel can do destination NAT"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        'nft add table ip natprobe && nft "add chain ip natprobe p { type nat hook prerouting priority -100 ; }"' \
        >/dev/null 2>&1; then
    echo "this host cannot create an nftables nat chain inside a container." >&2
    echo "Part 2's redirect needs it. The nf_nat/nft_chain_nat modules must be loaded" >&2
    echo "on the host; any machine already running Docker networking normally has them." >&2
    exit 1
fi

# 1. Containers. No data-plane network: the veth links are the only fabric.
#
# Every container is given an explicit command, which is what stops the base
# image's default CMD (`sshd -D -e`) from running. Only the production host is
# meant to answer on port 22, and a stray sshd on the honeypot would answer the
# attacker on the very port the lab is about.
IDLE_CMD=(sleep infinity)

# ip_forward is set at creation rather than by default_config/router.sh: Docker
# mounts /proc/sys read-only in an unprivileged container, and making the router
# privileged just to write one sysctl is more privilege than this lab needs.
log "starting router $ROUTER_CTN (forwarding, four segments)"
docker run -d --name "$ROUTER_CTN" --network=none \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=1 --hostname router \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

for h in prod honeypot admin attacker; do
    ctn="$( ctn_of "$h" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN --hostname "$h" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# 2. The veth/namespace plumbing runs in a privileged helper container rather
#    than on the host, so the learner needs docker access and nothing else.
#    helper_stop is trapped so the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0

# Put one end of a fresh veth pair into a container and rename it there.
plug() {
    local ctn="$1" want_if="$2" tmp="$3"
    local pid
    pid="$( docker inspect -f '{{.State.Pid}}' "$ctn" )"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}

wire_point_to_point() {
    local ctnA="$1" ifA="$2" ctnB="$3" ifB="$4"
    i=$(( i + 1 ))
    local ta="vp${i}a" tb="vp${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$ctnA" "$ifA" "$ta"
    plug "$ctnB" "$ifB" "$tb"
}

log "wiring external:   $ATTACKER_CTN($ATT_IF) <-> $ROUTER_CTN($R_EXT_IF)"
wire_point_to_point "$ATTACKER_CTN" "$ATT_IF"   "$ROUTER_CTN" "$R_EXT_IF"
log "wiring production: $PROD_CTN($PROD_IF) <-> $ROUTER_CTN($R_PROD_IF)"
wire_point_to_point "$PROD_CTN"     "$PROD_IF"  "$ROUTER_CTN" "$R_PROD_IF"
log "wiring honeypot:   $HONEY_CTN($HONEY_IF) <-> $ROUTER_CTN($R_HONEY_IF)"
wire_point_to_point "$HONEY_CTN"    "$HONEY_IF" "$ROUTER_CTN" "$R_HONEY_IF"
log "wiring management: $ADMIN_CTN($ADMIN_IF) <-> $ROUTER_CTN($R_MGMT_IF)"
wire_point_to_point "$ADMIN_CTN"    "$ADMIN_IF" "$ROUTER_CTN" "$R_MGMT_IF"

# 3. Apply the per-device starter configs (router first so forwarding and the
#    edge filter are up before anything crosses it, attacker last).
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. Check it with:  $LAB_DIR/scripts/status.sh"
