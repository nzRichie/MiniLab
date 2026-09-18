#!/usr/bin/env bash
# Spawn the botnet lab: a router with three legs, the inside server it protects,
# six field hosts and the site's admin on the middle leg, and the operator's
# controller and payload host on the third. Self-contained -- drives docker and
# the veth primitives directly, WITHOUT platform/startup.sh.
#
#   server  admin                              c2  loader
#   inside  \  field /                          \  /  operator
#   [ S1 ] --- router --- [ S2 ]      router --- [ S3 ]
#            128.0.0.1 / 128.1.0.1 / 128.2.0.1
#
# Each leg has a switch of its own, so the only path between legs is the router.
# That is the whole defensive argument: recruitment, tasking and payload
# delivery cross the router and a policy there can see them; spread from one
# field host to the next stays on S2 and no rule at the router can touch it.
#
# The router forwards and does not translate, so every packet still carries the
# address of the machine that sent it.
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

# Start the router first, forwarding on. ip_forward is set at creation rather
# than in a starter script because Docker mounts /proc/sys read-only in an
# unprivileged container, and explicitly to 0 on every other machine because
# "only the router forwards" is a fact the lab is built on.
log "starting router $ROUTER_CTN (three legs, forwarding on, no filtering yet)"
docker run -d --name "$ROUTER_CTN" --network=none --init \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=1 \
    --hostname router \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# The eleven hosts. --init everywhere: PID 1 would otherwise be `sleep infinity`,
# which never reaps, and every machine here forks something short-lived on a
# timer (each ssh the recruiter and the probes run, each command a bot runs).
for role in server admin host1 host2 host3 host4 host5 host6 c2 loader; do
    ctn="$( ctn_of "$role" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 \
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

# Put one end of a fresh veth pair into a container and rename it there.
plug() {   # <container> <interface name it should have> <temporary name>
    local ctn="$1" want_if="$2" tmp="$3" pid
    pid="$( docker inspect -f '{{.State.Pid}}' "$ctn" )"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}

# Wire a device into a switch: a veth pair, the host end renamed inside the
# device, the switch end renamed and added to that switch's bridge.
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

# --- inside leg (S1): router + server -------------------------------------
log "wiring inside: $ROUTER_CTN($IF_INSIDE) -> $SW_INSIDE_CTN"
wire_to_switch "$ROUTER_CTN" "$IF_INSIDE" "$( sw_port_of router-in )" "$SW_INSIDE_CTN"
wire_to_switch "$SERVER_CTN" "$IF_INSIDE" "$( sw_port_of server )" "$SW_INSIDE_CTN"

# --- field leg (S2): router + six hosts + admin ---------------------------
log "wiring field: $ROUTER_CTN($IF_FIELD) -> $SW_FIELD_CTN"
wire_to_switch "$ROUTER_CTN" "$IF_FIELD" "$( sw_port_of router-fld )" "$SW_FIELD_CTN"
for h in "${FIELD_HOSTS[@]}"; do
    wire_to_switch "$( ctn_of "$h" )" "$IF_FIELD" "$( sw_port_of "$h" )" "$SW_FIELD_CTN"
done
wire_to_switch "$ADMIN_CTN" "$IF_FIELD" "$( sw_port_of admin )" "$SW_FIELD_CTN"

# --- operator leg (S3): router + c2 + loader ------------------------------
log "wiring operator: $ROUTER_CTN($IF_OP) -> $SW_OP_CTN"
wire_to_switch "$ROUTER_CTN" "$IF_OP" "$( sw_port_of router-op )" "$SW_OP_CTN"
wire_to_switch "$C2_CTN" "$IF_OP" "$( sw_port_of c2 )" "$SW_OP_CTN"
wire_to_switch "$LOADER_CTN" "$IF_OP" "$( sw_port_of loader )" "$SW_OP_CTN"

# Preload the two netfilter modules the learner's own rules need. hashlimit and
# recent are what Part 4's second move is written with, and a learner types
# those rules inside an unprivileged container that cannot autoload a module:
# the failure otherwise reads as "No chain/target/match by that name", which
# points nowhere near a missing module.
#
# The load runs the HOST's own modprobe through the host mount namespace
# (nsenter -t 1 -m), not the helper's: the module tree lives under the host's
# /lib/modules, which the helper does not mount, and the helper's Alpine kmod
# cannot read this kernel's zstd-compressed modules anyway. Under a rootful
# daemon this loads them; under a rootless daemon pid 1 belongs to a user
# namespace the helper cannot write, and the load is skipped with a note. Most
# machines already running Docker have these modules loaded (Docker's own
# networking pulls in much of xt), so the skip is usually harmless; the note
# names the failure a learner would otherwise meet mid-Part 4.
log "preloading xt_hashlimit and xt_recent (the learner's rate-limit rules need them)"
for mod in xt_hashlimit xt_recent; do
    if helper nsenter -t 1 -m -u -n -i modprobe "$mod" >/dev/null 2>&1; then
        log "  loaded $mod"
    elif helper sh -c "grep -qw '${mod#xt_}' /proc/net/ip_tables_matches 2>/dev/null" \
         || lsmod 2>/dev/null | grep -qw "$mod"; then
        log "  $mod already present"
    else
        log "  note: could not load $mod; Part 4's rate-limit move may fail on this host"
    fi
done

# Apply the per-device starter configs in the order lib.sh defines: the router
# first so there is a path between the legs, then the loader and server so there
# is something to fetch and attack, then the field hosts and the admin.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec -i "$ctn" "/home/${d}.sh"
done

log "lab is up. Nothing is running an attack yet: the controller is a program"
log "you start on the c2, and the population is empty until you install it."
log "Check it with:  $LAB_DIR/scripts/status.sh"
