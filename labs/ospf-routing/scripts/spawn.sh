#!/usr/bin/env bash
# Spawn the OSPF routing lab: five FRR routers wired in the pentagon-plus-chord
# from lib.sh, each with one host behind it. Self-contained -- drives docker and
# the veth primitives directly, WITHOUT platform/startup.sh. Every router-to-router
# link is a Layer-3 point-to-point veth pair; there is no switch and no OVS.
#
# The network comes up UNCONFIGURED on purpose. Interfaces exist, are named, and
# are up; FRR is running with zebra and ospfd; and nothing else is set. No router
# holds an address, no router runs OSPF, and no host has a default route. Every one
# of those is something the learner types, and default_config/ is what enforces it.
#
# The one thing spawn does configure is the per-link delay, because a learner
# cannot measure a latency difference that is not there. Each link carries the
# one-way delay named in lib.sh, applied with netem at both ends.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

# Docker reachability is the only host prerequisite. No frr or tc check on the
# host: both live inside the image.
command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and can this account reach it? (try: docker info)" >&2
    exit 1
}

if docker ps -a --format '{{.Names}}' | grep -q "$LAB_FILTER"; then
    echo "Lab already spawned (containers matching ${LAB_FILTER} exist). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# 1. Containers.
#
#    Routers get the three capabilities FRR's zebra asks for at startup
#    (net_admin + net_raw + sys_admin; with only the first two, zebra, mgmtd and
#    ospfd all fail on cap_set_proc while staticd runs, which looks like a broken
#    image rather than a missing capability). IP forwarding is on from birth so a
#    router forwards the first packet it sees, and rp_filter is off because OSPF
#    can pick asymmetric paths that strict reverse-path filtering would drop.
#
#    Hosts run the same image with the CMD overridden, so FRR is installed and not
#    running. They get net_admin to hold an address and, in Part 4, to let a
#    learner start a routing daemon; net_raw so tcpdump can see the OSPF hellos
#    arriving on the host link, which is the observation Part 5 acts on.
for r in "${ROUTERS[@]}"; do
    rc="$( router_ctn "$r" )"
    log "starting router $rc"
    docker run -d --init --name "$rc" --network=none \
        --cap-add=NET_ADMIN --cap-add=NET_RAW --cap-add=SYS_ADMIN \
        --sysctl net.ipv4.ip_forward=1 \
        --sysctl net.ipv4.conf.all.rp_filter=0 \
        --sysctl net.ipv4.conf.default.rp_filter=0 \
        --hostname "$r" \
        "$NODE_IMAGE" >/dev/null

    hc="$( host_ctn "$r" )"
    log "starting host $hc"
    docker run -d --init --name "$hc" --network=none \
        --cap-add=NET_ADMIN --cap-add=NET_RAW --cap-add=SYS_ADMIN \
        --hostname "${r}-host" \
        "$NODE_IMAGE" sleep infinity >/dev/null
done

# 2. Privileged wiring via the helper container (docker access is all the learner
#    needs; the helper holds the netlink privileges). Trapped so it always goes,
#    including on an interrupted spawn.
helper_start
trap helper_stop EXIT

i=0
# Move one end of a fresh veth pair into a container, rename and up it.
plug() {
    local ctn="$1" want_if="$2" tmp="$3" pid
    pid="$( docker inspect -f '{{.State.Pid}}' "$ctn" )"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}
# One point-to-point veth between two containers' named interfaces.
wire() {
    local ctnA="$1" ifA="$2" ctnB="$3" ifB="$4"
    i=$(( i + 1 ))
    local ta="v${i}a" tb="v${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$ctnA" "$ifA" "$ta"
    plug "$ctnB" "$ifB" "$tb"
}
ctn_pid() { docker inspect -f '{{.State.Pid}}' "$1"; }

# 2a. Router-to-router links. For link "a b", a's interface is port_<B>.
while read -r a b _ _ _ _; do
    [ -z "$a" ] && continue
    log "wiring $( uc "$a" ) <-> $( uc "$b" )"
    wire "$( router_ctn "$a" )" "$( peer_if "$b" )" \
         "$( router_ctn "$b" )" "$( peer_if "$a" )"
done < <( each_link )

# 2b. Host links (router <-> its own host).
for r in "${ROUTERS[@]}"; do
    log "wiring $( uc "$r" ) <-> its host"
    wire "$( router_ctn "$r" )" "$HOST_IF_ROUTER" "$( host_ctn "$r" )" "$HOST_IF_HOST"
done

# 3. Per-link delay.
#
#    Applied at both ends of each link, so a link listed as 5 ms in lib.sh adds
#    5 ms in each direction and shows up as about 10 ms of round-trip time. Host
#    links get none: a learner measuring a path should be measuring the routers
#    between them, not the last metre.
#
#    Attached from the helper, not from inside each router, because the first
#    netem qdisc on a machine has to autoload the kernel's sch_netem module and
#    only a process holding CAP_SYS_MODULE in the initial user namespace may
#    trigger that. Under a rootless daemon no container holds it, so the module
#    has to be resident already; that is what the check below is for.
if netem_available; then
    while read -r a b _ _ _ delay; do
        [ -z "$a" ] && continue
        log "delaying $( uc "$a" ) <-> $( uc "$b" ) by ${delay} ms each way"
        helper_netem "$( ctn_pid "$( router_ctn "$a" )" )" "$( peer_if "$b" )" "$delay"
        helper_netem "$( ctn_pid "$( router_ctn "$b" )" )" "$( peer_if "$a" )" "$delay"
    done < <( each_link )
else
    echo "[spawn] WARNING: the kernel's sch_netem module is not available to a container," >&2
    echo "[spawn]          so every link will have the same near-zero latency and Part 3" >&2
    echo "[spawn]          of the handout has nothing to measure. Load it once on this" >&2
    echo "[spawn]          machine with:  sudo modprobe sch_netem" >&2
    echo "[spawn]          then tear this lab down and spawn it again." >&2
fi

# 4. Wait for each router's FRR, then apply its starter config -- which is the
#    script that makes sure the router is BLANK. It restarts FRR against an empty
#    frr.conf, so it also proves vtysh comes back before the lab is handed over.
for r in "${ROUTERS[@]}"; do
    rc="$( router_ctn "$r" )"
    log "waiting for FRR in $rc"
    wait_for_vtysh "$rc"
    log "applying default_config/${r}.sh (leaves $( uc "$r" ) unconfigured)"
    docker cp "$LAB_DIR/default_config/${r}.sh" "$rc:/home/${r}.sh"
    docker exec "$rc" chmod 755 "/home/${r}.sh"
    docker exec "$rc" "/home/${r}.sh"
done

# 5. Hosts: their own address, no default route, their own banner.
for r in "${ROUTERS[@]}"; do
    hc="$( host_ctn "$r" )"
    log "configuring $hc ($( host_ip "$r" ), no default route)"
    docker cp "$LAB_DIR/default_config/host-setup.sh" "$hc:/home/host-setup.sh"
    docker exec "$hc" chmod 755 /home/host-setup.sh
    docker exec "$hc" /home/host-setup.sh \
        "$( host_ip "$r" )/${HOST_PREFIXLEN}" "$( host_gw "$r" )" "$( host_banner "$r" )"
done

# 6. There is no convergence to wait for. Nothing in this network is configured,
#    so no adjacency can form and no route can be learned until the learner starts
#    typing. Saying so is the point: a lab that came up converged would have done
#    the exercise for them.
log "lab is up, and deliberately unconfigured: no addresses, no OSPF, no default routes."
log "Check what it does and does not have with:  $LAB_DIR/scripts/status.sh"
