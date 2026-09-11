#!/usr/bin/env bash
# Spawn the NAT and port-forwarding lab: a private segment behind one edge
# router, and one host on the far side. Self-contained — drives docker + the
# veth/OVS primitives directly, WITHOUT the full platform/startup.sh pipeline
# (proposal RQ1).
#
#   inside-1  --+
#   inside-2  --+-- S1 -- router -- outside
#   webserver --+
#
# The private segment is switched, because three machines share it; the outside
# link holds two machines and is a point-to-point veth pair with no switch on it,
# because nothing in this lab is about Layer 2.
#
# Everything except the translation rules arrives configured: addresses, routes
# and both web services are up the moment spawn finishes. The router forwards
# between the two segments and translates nothing, and every rule that changes
# that is the learner's to write.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

# Open vSwitch is NOT required on the host: every ovs-vsctl call in this lab runs
# inside the switch container, whose image ships OVS. Docker reachability is the
# real prerequisite, and it covers an unreachable daemon as well as a stopped one.
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

# Every rule in this lab is a nat-type base chain, and registering one needs the
# nf_tables NAT machinery available inside the container's namespace. Loading a
# netfilter module requires privilege in the initial namespace, which a rootless
# daemon's containers do not have, so on a host where nothing has ever loaded
# nft_chain_nat the learner's first command in Part 2 would fail with an error
# they have no way to interpret. Fail here instead, with the reason.
#
# The probe registers a chain at the postrouting hook and adds a masquerade rule,
# rather than only creating a table, because a table costs nothing to create on a
# host that cannot do NAT at all.
log "checking this host can register an nftables NAT chain inside a container"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        'nft add table ip natprobe &&
         nft "add chain ip natprobe p { type nat hook postrouting priority srcnat ; policy accept ; }" &&
         nft add rule ip natprobe p masquerade' >/dev/null 2>&1; then
    echo "this host cannot register an nftables NAT chain inside a container." >&2
    echo "Every part of this lab needs one. The nf_tables, nft_chain_nat, nf_nat and" >&2
    echo "nf_conntrack modules must be loaded on the host; any machine already running" >&2
    echo "Docker's own networking normally has them." >&2
    exit 1
fi

# Every lab container is given an explicit command, which is what stops the base
# image's default CMD (sshd -D -e) from running and putting an SSH service on
# every host in a lab that places none. A stray listener matters more here than
# usual: Part 3 has the learner read a connection refused off the router, and a
# port that answered would change what they see.
IDLE_CMD=(sleep infinity)

# ping_group_range is pinned so that ping prints the same thing on a rootful and
# a rootless daemon. iputils ping opens a datagram ICMP socket when the caller's
# group is inside this range and falls back to a raw socket when it is not, and
# the two paths report an unanswered request differently. A rootful daemon ships
# the range as 0 2147483647 and a rootless one as 65534 65534, so without this
# the handout would quote statistics half a class does not see. "0 0" covers the
# container's root group, which every lab process runs as, and stays inside the
# gid map a user namespace allows.
PING_SYSCTL=(--sysctl "net.ipv4.ping_group_range=0 0")

# The router.
#
# ip_forward is set here rather than in default_config/router.sh because Docker
# mounts /proc/sys read-only in an unprivileged container.
#
# send_redirects is turned OFF, and it is the kernel default that is being
# overridden. Part 5 has the router forward a packet back out of the interface it
# arrived on, which is exactly the condition a router sends an ICMP redirect
# under. The redirect is generated after the destination has already been
# rewritten, so what the client would receive is advice about an address it never
# sent to, arriving in the middle of the one capture the section asks it to read.
# ICMP redirects are the subject of the addressing-and-static-routing lab; here
# they are noise over the measurement.
#
# NET_ADMIN is what lets the learner load the ruleset without the container being
# privileged.
log "starting router $ROUTER_CTN (forwarding on, redirects off, NET_ADMIN for nftables)"
docker run -d --name "$ROUTER_CTN" --network=none \
    --cap-add=NET_ADMIN --hostname router \
    --sysctl net.ipv4.ip_forward=1 \
    --sysctl net.ipv4.conf.all.send_redirects=0 \
    --sysctl net.ipv4.conf.default.send_redirects=0 \
    "${PING_SYSCTL[@]}" \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# The switch on the private segment.
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

# The four end hosts.
#
# --init on the two that run lighttpd. Their PID 1 would otherwise be `sleep
# infinity`, which never calls wait(), so every lighttpd child that exits stays
# in the process table as a zombie and `pkill -x lighttpd` in reset.sh starts
# matching dead processes.
for h in webserver outside; do
    ctn="$( ctn_of "$h" )"
    log "starting $ctn (init, runs a web service)"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --hostname "$h" \
        "${PING_SYSCTL[@]}" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done
for h in inside-1 inside-2; do
    ctn="$( ctn_of "$h" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN --hostname "$h" \
        "${PING_SYSCTL[@]}" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# The private segment's bridge. STP stays OFF: there is no loop anywhere in this
# lab, and STP would hold every port in listening/learning for 15 to 30 seconds
# and delay the learner's first ping for no reason.
log "waiting for Open vSwitch in $SW_CTN"
for _ in $(seq 1 40); do
    if docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1; then break; fi
    sleep 0.5
done
log "creating bridge br0 in $SW_CTN"
docker exec "$SW_CTN" ovs-vsctl \
    -- add-br br0 \
    -- set bridge br0 stp_enable=false \
    -- set-fail-mode br0 standalone >/dev/null

# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else. helper_stop
# is trapped so the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0

# Put one end of a fresh veth pair into a container, rename it there and bring it
# up.
plug() {   # <container> <interface name it should have> <temporary name>
    local ctn="$1" want_if="$2" tmp="$3" pid
    pid="$( docker inspect -f '{{.State.Pid}}' "$ctn" )"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}

# Wire a device into the private segment's bridge. The switch end is brought up
# and added to br0; the switch is not what this lab is about and a learner has no
# reason to configure one.
wire_to_switch() {   # <device> <interface it should have>
    local dev="$1" dev_if="$2" port pid ta tb
    port="$( sw_port_of "$dev" )"
    i=$(( i + 1 )); ta="vn${i}a"; tb="vn${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$( ctn_of "$dev" )" "$dev_if" "$ta"
    pid="$( docker inspect -f '{{.State.Pid}}' "$SW_CTN" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$port"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$port" up
    docker exec "$SW_CTN" ovs-vsctl add-port br0 "$port" >/dev/null
}

for h in "${INSIDE_HOSTS[@]}"; do
    log "wiring $( ctn_of "$h" )($HOST_IF) -> $SW_CTN port $( sw_port_of "$h" )"
    wire_to_switch "$h" "$HOST_IF"
done
log "wiring $ROUTER_CTN($R_IN_IF) -> $SW_CTN port $( sw_port_of router )"
wire_to_switch router "$R_IN_IF"

# The outside link: two machines, no switch.
log "wiring $ROUTER_CTN($R_OUT_IF) <-> $OUTSIDE_CTN($OUT_IF)"
i=$(( i + 1 ))
helper ip link add "vp${i}a" type veth peer name "vp${i}b"
plug "$ROUTER_CTN"  "$R_OUT_IF" "vp${i}a"
plug "$OUTSIDE_CTN" "$OUT_IF"   "vp${i}b"

# Apply the per-device starter configs: the router first, so both segments are
# addressed before anything crosses them.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. The router forwards between both segments and translates nothing."
log "Check it with:  $LAB_DIR/scripts/status.sh"
