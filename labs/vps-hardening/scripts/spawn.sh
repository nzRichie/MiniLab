#!/usr/bin/env bash
# Spawn the VPS provisioning and hardening lab: a server delivered unhardened, a
# router, an administrative client on a management segment, and a host outside
# both. Self-contained — drives docker + the veth primitives directly, WITHOUT
# the full platform/startup.sh pipeline (proposal RQ1).
#
# Every segment holds one host, so there is no switch and no OVS anywhere in this
# lab. Three point-to-point veth pairs meet at the router:
#
#   outside --- router --- server
#                  |
#                admin
#
# The router forwards between all three and filters nothing, which is what makes
# the server's own configuration the whole of its defence.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

# Open vSwitch is not a requirement: this lab runs no switch. Docker reachability
# is the real prerequisite, and it covers an unreachable daemon as well as a
# stopped one.
command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and can this account reach it? (try: docker info)" >&2
    exit 1
}

if docker ps -a --format '{{.Names}}' | grep -qx "$SERVER_CTN"; then
    echo "Lab already spawned ($SERVER_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# Part 5's packet filter is an nftables base chain at the input hook. Registering
# one needs the nf_tables machinery available inside the container's namespace,
# and autoloading a netfilter module needs privilege in the initial namespace,
# which a rootless daemon's containers do not have. On a host where nothing has
# ever loaded it, the learner's first `nft add table` would fail halfway through
# Part 5 with an error they have no way to interpret. Fail here instead, with the
# reason.
log "checking this host can register an nftables input chain inside a container"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        'nft add table inet nftprobe && nft "add chain inet nftprobe c { type filter hook input priority filter ; policy accept ; }"' \
        >/dev/null 2>&1; then
    echo "this host cannot register an nftables filter chain inside a container." >&2
    echo "Part 5 needs one. The nf_tables/nft_chain_filter modules must be loaded on" >&2
    echo "the host; any machine already running Docker networking normally has them." >&2
    exit 1
fi

# Every container is given an explicit command, which is what stops the base
# image's default CMD (`sshd -D -e`) from running. Only the server is meant to
# answer on port 22, and a stray sshd on the outside host would put a listener on
# the very port the lab's sweeps are read for.
IDLE_CMD=(sleep infinity)

# ip_forward is set at creation rather than by default_config/router.sh: Docker
# mounts /proc/sys read-only in an unprivileged container, and making the router
# privileged just to write one sysctl is more privilege than this lab needs.
log "starting router $ROUTER_CTN (forwarding, three segments)"
docker run -d --name "$ROUTER_CTN" --network=none \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=1 \
    --hostname router \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# --init on the server, and only on the server. Its PID 1 would otherwise be
# `sleep infinity`, which never calls wait(), so every sshd and lighttpd child
# that exits stays in the process table as a zombie. That is not merely untidy:
# `pgrep -x sshd` then lists the zombies alongside the listener, and a learner
# who reloads sshd with a pid picked out of pgrep sends SIGHUP to a dead process
# and sees no error and no reload. docker-init reaps them, so the process table
# on the machine the learner inspects holds what they expect it to hold.
#
# NET_ADMIN is what lets the learner load Part 5's ruleset without the container
# being privileged.
log "starting server $SERVER_CTN (init, NET_ADMIN for nftables)"
docker run -d --name "$SERVER_CTN" --network=none --init \
    --cap-add=NET_ADMIN --hostname server \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

for h in admin outside; do
    ctn="$( ctn_of "$h" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN --hostname "$h" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else. helper_stop
# is trapped so the helper goes away however this script exits.
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

log "wiring external:   $OUTSIDE_CTN($OUT_IF) <-> $ROUTER_CTN($R_EXT_IF)"
wire_point_to_point "$OUTSIDE_CTN" "$OUT_IF"   "$ROUTER_CTN" "$R_EXT_IF"
log "wiring server:     $SERVER_CTN($SRV_IF) <-> $ROUTER_CTN($R_SRV_IF)"
wire_point_to_point "$SERVER_CTN"  "$SRV_IF"   "$ROUTER_CTN" "$R_SRV_IF"
log "wiring management: $ADMIN_CTN($ADMIN_IF) <-> $ROUTER_CTN($R_MGMT_IF)"
wire_point_to_point "$ADMIN_CTN"   "$ADMIN_IF" "$ROUTER_CTN" "$R_MGMT_IF"

# Apply the per-device starter configs: the router first so the three segments
# are addressed before anything crosses them, then the server, then the two
# clients.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up, and the server is as unhardened as it ships."
log "Check it with:  $LAB_DIR/scripts/status.sh"
