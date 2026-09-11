#!/usr/bin/env bash
# Spawn the DNS cache-poisoning lab: a caching resolver and the host that trusts
# it on one switched campus segment, the authoritative server for uni.lab one
# router hop away, and an attacker on a third link that sees neither of them.
# Self-contained — drives docker + the veth/OVS primitives directly, WITHOUT the
# full platform/startup.sh pipeline (proposal RQ1).
#
#   victim ---+
#             +-- S1 (OVS) -- router --+-- auth      (uni.lab, 400 ms away)
#   resolver -+                        +-- attacker  (attack.lab, and the spoofer)
#
# The attacker's link carries none of the resolver's traffic to the authoritative
# server, which is the whole premise: it has to guess what it cannot see.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$SW_CTN"; then
    echo "Lab already spawned ($SW_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# 1. Containers (no data-plane network; the veth links + OVS bridge are the only
#    fabric).
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

# Every lab container is given an explicit command, which is what stops the base
# image's default CMD (sshd -D -e) from running and putting an SSH service on
# every host in a lab that places none.
IDLE_CMD=(sleep infinity)

# Both sysctls are set at creation rather than by default_config/router.sh:
# Docker mounts /proc/sys read-only in an unprivileged container, and making the
# router privileged just to write two values is more privilege than this lab
# needs.
#
# rp_filter is the one that decides whether this lab has an attack in it at all.
# Linux ships it at 1 in a Docker container, which makes the router drop any
# packet whose source address it would not route back out of the interface the
# packet arrived on. Every forged answer the attacker sends claims to come from
# 107.2.0.10, which the router reaches through a different interface, so with
# rp_filter left at 1 not one of them reaches the resolver: measured at zero
# arrivals out of 843,616 packets per second. Turning it off is what makes this
# router an ordinary internet router, which forwards a packet on its destination
# address and checks nothing about its source. The kernel takes the larger of
# conf.all and the per-interface value, and a per-interface value is copied from
# conf.default when the interface appears, so both have to be zero here.
log "starting router $ROUTER_CTN (forwarding, no reverse-path filtering)"
docker run -d --name "$ROUTER_CTN" --network=none \
    --cap-add=NET_ADMIN --hostname router \
    --sysctl net.ipv4.ip_forward=1 \
    --sysctl net.ipv4.conf.all.rp_filter=0 \
    --sysctl net.ipv4.conf.default.rp_filter=0 \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# NET_RAW is what lets the attacker forge a source address on a raw socket, and
# every image in this lab is the same image, so it is granted where it is needed
# and nowhere else. The resolver, the authoritative server and the victim get
# NET_ADMIN alone, which is all that addressing an interface takes.
for d in resolver victim auth; do
    ctn="$(ctn_of "$d")"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=NET_ADMIN --hostname "$d" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

log "starting $ATTACKER_CTN (raw sockets, for forging a source address)"
docker run -d --name "$ATTACKER_CTN" --network=none \
    --cap-add=NET_ADMIN --cap-add=NET_RAW --hostname attacker \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# 2. The campus segment's OVS bridge. Single switch, no loops, so STP stays OFF
#    (it would hold ports in listening/learning for 15-30s and delay the first
#    packet).
log "waiting for Open vSwitch in $SW_CTN"
for _ in $(seq 1 40); do
    if docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1; then break; fi
    sleep 0.5
done
log "creating bridge br0"
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

plug() {   # put one end of a fresh veth pair into a container and rename it
    local ctn="$1" want_if="$2" tmp="$3"
    local pid
    pid="$(docker inspect -f '{{.State.Pid}}' "$ctn")"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}

# 3a. The two point-to-point links out of the router. No switch and no bridge:
#     the router and the far host are the only two devices on each, which is what
#     keeps the attacker off the path between the resolver and uni.lab.
wire_point_to_point() {
    local ctnA="$1" ifA="$2" ctnB="$3" ifB="$4"
    i=$((i + 1))
    local ta="vp${i}a" tb="vp${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$ctnA" "$ifA" "$ta"
    plug "$ctnB" "$ifB" "$tb"
}
log "wiring $ROUTER_CTN($R_AUTH_IF) <-> $AUTH_CTN($EXT_IF)"
wire_point_to_point "$ROUTER_CTN" "$R_AUTH_IF" "$AUTH_CTN" "$EXT_IF"
log "wiring $ROUTER_CTN($R_HOSTILE_IF) <-> $ATTACKER_CTN($EXT_IF)"
wire_point_to_point "$ROUTER_CTN" "$R_HOSTILE_IF" "$ATTACKER_CTN" "$EXT_IF"

# 3b. The campus segment: the router's campus interface and both campus hosts
#     attach to br0.
wire_to_switch() {
    local ctn="$1" host_if="$2" sw_port="$3"
    i=$((i + 1))
    local ta="vh${i}a" tb="vh${i}b" spid
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$ctn" "$host_if" "$ta"
    spid="$(docker inspect -f '{{.State.Pid}}' "$SW_CTN")"
    helper ip link set "$tb" netns "$spid"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$tb" name "$sw_port"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$sw_port" up
    docker exec "$SW_CTN" ovs-vsctl add-port br0 "$sw_port" >/dev/null
}
log "wiring campus: $ROUTER_CTN($R_CAMPUS_IF) -> $SW_CTN (port $(sw_port_of router))"
wire_to_switch "$ROUTER_CTN" "$R_CAMPUS_IF" "$(sw_port_of router)"
for h in "${CAMPUS_HOSTS[@]}"; do
    log "wiring campus: $(ctn_of "$h")($HOST_IF) -> $SW_CTN (port $(sw_port_of "$h"))"
    wire_to_switch "$(ctn_of "$h")" "$HOST_IF" "$(sw_port_of "$h")"
done

# 4. Apply the per-device starter configs, in the order lib.sh sets: the router
#    first so forwarding is up before anything crosses it, then the two name
#    servers, then the resolver that queries them, then the victim.
for d in "${DEVICES[@]}"; do
    ctn="$(ctn_of "$d")"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

# 5. Publish the zone's public key to the resolver's operator.
#
#    A trust anchor is a key a resolver is configured with out of band, because
#    there is nothing above uni.lab in this lab to vouch for it. Reading it off
#    the authoritative server and writing it to a file on the resolver is what
#    stands in here for the zone operator publishing it; the resolver does not
#    install it, and nothing validates anything until Part 2 does.
log "publishing uni.lab's key signing key to $RESOLVER_CTN:$TRUST_ANCHOR"
anchor=""
for _ in $(seq 1 60); do
    anchor="$( docker exec "$AUTH_CTN" dig +short +timeout=2 +tries=1 \
        @127.0.0.1 -p 5353 "$TARGET_ZONE" DNSKEY 2>/dev/null \
        | awk '$1 == "257" { $1=$1; print; exit }' )"
    [ -n "$anchor" ] && break
    sleep 1
done
if [ -z "$anchor" ]; then
    echo "[spawn] the authoritative server produced no key signing key for $TARGET_ZONE" >&2
    exit 1
fi
key="$( echo "$anchor" | cut -d' ' -f4- | tr -d ' ' )"
alg="$( echo "$anchor" | cut -d' ' -f3 )"
docker exec -i "$RESOLVER_CTN" sh -c "cat > $TRUST_ANCHOR" <<EOF
// The public half of uni.lab's key signing key, as its operator published it.
// A resolver that installs this can check every signature in the zone against
// it. Nothing installs it automatically: see /etc/bind/trust-anchors.conf.
trust-anchors {
    "${TARGET_ZONE}." static-key 257 3 ${alg} "${key}";
};
EOF

log "lab is up. Check it with:  $LAB_DIR/scripts/status.sh"
