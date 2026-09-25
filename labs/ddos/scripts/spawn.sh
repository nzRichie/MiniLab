#!/usr/bin/env bash
# Spawn the ddos lab: a router with three legs and both shapers, the victim it
# fronts, four flood sources and two reflectors and the site's admin on the
# field leg, and the console on the third. Self-contained -- drives docker and
# the veth/OVS primitives directly, WITHOUT platform/startup.sh.
#
#   server                                            c2  loader
#   inside  \     field /                              \  /  operator
#   [ S1 ] --- router --- [ S2 ]           router --- [ S3 ]
#            129.0.0.1 / 129.1.0.1 / 129.2.0.1
#
# Both shapers hang off the router: 1 Mbit/s toward the victim on the inside
# egress, 256 kbit/s away from it on the field egress. They are attached from
# inside the router container by default_config/router.sh, not from the helper:
# sch_tbf autoloads on demand from a container holding only NET_ADMIN, on a
# machine where the module is on disk and absent from lsmod.
#
# The reflectors sit on the field segment with the sources, so a spoofed query
# never crosses the router and everything the victim's network sees is reply
# traffic from two well-behaved servers.
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

IDLE_CMD=(sleep infinity)

# The router is privileged because the learner writes per-interface rp_filter
# and log_martians on it at the moment Stage 1's first mitigation asks for them,
# and /proc/sys is read-only in a container with any capability set short of
# that. rp_filter is pinned to 0 on `all` and `default` at creation: a fresh
# container inherits this host's own value, which is 1 on most machines, and
# strict uRPF that is already on would make Stage 1's step a no-op on some
# machines and not others.
log "starting router $ROUTER_CTN (three legs, forwarding on, uRPF off, both shapers)"
docker run -d --name "$ROUTER_CTN" --network=none --init --privileged \
    --sysctl net.ipv4.ip_forward=1 \
    --sysctl net.ipv4.conf.all.rp_filter=0 \
    --sysctl net.ipv4.conf.default.rp_filter=0 \
    --hostname router \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# The victim. Privileged for the same reason as the router: turning syncookies
# on is Stage 2's mitigation and the learner types it. The three --sysctl values
# are the undefended baseline, and tcp_no_metrics_save=1 is the one that is not
# tuning: without it the kernel exempts any peer it holds TCP metrics for from
# the pre-emptive SYN drop, the admin's own probe makes the admin such a peer,
# and the flood denies service to nobody. `ip tcp_metrics flush` cannot be used
# instead -- it returns EPERM under a rootless daemon.
log "starting victim $SERVER_CTN (syncookies off, syn backlog $SYN_BACKLOG)"
docker run -d --name "$SERVER_CTN" --network=none --init --privileged \
    --sysctl net.ipv4.ip_forward=0 \
    --sysctl net.ipv4.tcp_syncookies=0 \
    --sysctl "net.ipv4.tcp_max_syn_backlog=$SYN_BACKLOG" \
    --sysctl net.ipv4.tcp_no_metrics_save=1 \
    --hostname server \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# The four sources hold NET_RAW as well as NET_ADMIN: a forged source address
# and a hand-built SYN both need a raw socket, and the RST drop each source
# applies in Stage 2 needs iptables. Everything else on the lab holds NET_ADMIN
# alone.
for role in host1 host2 host3 host4; do
    ctn="$( ctn_of "$role" )"
    log "starting source $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --cap-add=NET_RAW \
        --sysctl net.ipv4.ip_forward=0 \
        --hostname "$role" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# The two reflectors, the admin, the console and the loader. None of them ever
# forges anything.
for role in host5 host6 admin c2 loader; do
    ctn="$( ctn_of "$role" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN \
        --sysctl net.ipv4.ip_forward=0 \
        --hostname "$role" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# The three switches. --cap-add=ALL minus SYS_RESOURCE is what the
# mini-internet's own switch containers run with; ovs-vswitchd needs most of it,
# and SYS_RESOURCE is dropped because raising RLIMIT_MEMLOCK is exactly what
# fails in a user namespace.
for sw in "${SWITCHES[@]}"; do
    ctn="$( ctn_of "$sw" )"
    log "starting switch $ctn"
    docker run -d --name "$ctn" --network=none \
        --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$sw" \
        "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null
done

for sw in "${SWITCHES[@]}"; do
    ctn="$( ctn_of "$sw" )"
    log "waiting for Open vSwitch in $ctn"
    for _ in $(seq 1 60); do
        if docker exec "$ctn" ovs-vsctl show >/dev/null 2>&1; then break; fi
        sleep 0.5
    done
    docker exec "$ctn" ovs-vsctl show >/dev/null 2>&1 || {
        echo "Open vSwitch did not come up in $ctn" >&2; exit 1; }
    log "creating bridge $BR in $ctn"
    docker exec "$ctn" ovs-vsctl --may-exist add-br "$BR" >/dev/null
    docker exec "$ctn" ovs-vsctl set bridge "$BR" stp_enable=false >/dev/null
done

# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else. helper_stop
# is trapped so the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0

plug() {   # <container> <interface name it should have> <temporary name>
    local ctn="$1" want_if="$2" tmp="$3" pid
    pid="$( docker inspect -f '{{.State.Pid}}' "$ctn" )"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}

wire_to_switch() {   # <container> <interface inside it> <switch port name> <switch container>
    i=$(( i + 1 ))
    local ta="vc${i}a" tb="vc${i}b" pid
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    pid="$( docker inspect -f '{{.State.Pid}}' "$4" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$3"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$3" up
    docker exec "$4" ovs-vsctl add-port "$BR" "$3" >/dev/null
}

# --- inside leg (S1): router + victim --------------------------------------
log "wiring inside: $ROUTER_CTN($IF_INSIDE) -> $SW_INSIDE_CTN"
wire_to_switch "$ROUTER_CTN" "$IF_INSIDE" "$( sw_port_of router-in )" "$SW_INSIDE_CTN"
wire_to_switch "$SERVER_CTN" "$IF_INSIDE" "$( sw_port_of server )" "$SW_INSIDE_CTN"

# --- field leg (S2): router + four sources + two reflectors + admin --------
log "wiring field: $ROUTER_CTN($IF_FIELD) -> $SW_FIELD_CTN"
wire_to_switch "$ROUTER_CTN" "$IF_FIELD" "$( sw_port_of router-fld )" "$SW_FIELD_CTN"
for h in "${FIELD_HOSTS[@]}"; do
    wire_to_switch "$( ctn_of "$h" )" "$IF_FIELD" "$( sw_port_of "$h" )" "$SW_FIELD_CTN"
done
wire_to_switch "$ADMIN_CTN" "$IF_FIELD" "$( sw_port_of admin )" "$SW_FIELD_CTN"

# --- operator leg (S3): router + console + loader --------------------------
log "wiring operator: $ROUTER_CTN($IF_OP) -> $SW_OP_CTN"
wire_to_switch "$ROUTER_CTN" "$IF_OP" "$( sw_port_of router-op )" "$SW_OP_CTN"
wire_to_switch "$C2_CTN" "$IF_OP" "$( sw_port_of c2 )" "$SW_OP_CTN"
wire_to_switch "$LOADER_CTN" "$IF_OP" "$( sw_port_of loader )" "$SW_OP_CTN"

# Apply the per-device starter configs in the order lib.sh defines: the router
# first so there is a path between the legs and both shapers are attached, then
# the victim and the loader, then the reflectors, the sources, and the admin.
#
# `docker exec -i` and not `docker exec`: without -i the container's stdin is
# closed, every heredoc inside these scripts writes an empty file, and each one
# still exits 0.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec -i "$ctn" "/home/${d}.sh"
done

log "lab is up. Nothing is flooding anything: a flood is four bounded runs you"
log "start from the console, and each one ends on its own."
log "Check it with:  $LAB_DIR/scripts/status.sh"
