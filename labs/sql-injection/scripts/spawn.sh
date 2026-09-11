#!/usr/bin/env bash
# Spawn the SQL injection and least-privilege lab: the storefront, the database
# and the attacker's machine on one switched segment. Self-contained -- drives
# docker + the veth primitives directly, WITHOUT the full platform/startup.sh
# pipeline.
#
#   web (122.0.0.10) ----\
#                         [ S1 ]---- attacker (122.0.0.66)
#   db  (122.0.0.20) ----/
#
# There is no router. The rule Part 2C writes is an input filter on the database
# host itself, so it needs no boundary device to sit on, and every packet the
# database sees still carries the address of the host that sent it, which is
# what lets that rule name the web tier.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and can this account reach it? (try: docker info)" >&2
    exit 1
}

if docker ps -a --format '{{.Names}}' | grep -qx "$DB_CTN"; then
    echo "Lab already spawned ($DB_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# Part 2C registers an nftables chain at the input hook. Registering a base chain
# needs the nf_tables machinery in the container's namespace, and autoloading it
# needs privilege in the initial namespace, which a rootless daemon's containers
# do not have. Fail here with the reason rather than halfway through Part 2C with
# an error the learner would read as their own mistake.
log "checking this host can register an nftables input chain inside a container"
if ! docker run --rm --cap-add=NET_ADMIN "$HOST_IMAGE" sh -c \
        "nft add table inet nftprobe \
         && nft 'add chain inet nftprobe c { type filter hook input priority filter ; policy accept ; }' \
         && nft add rule inet nftprobe c tcp dport 3306 drop" \
        >/dev/null 2>&1; then
    echo "this host cannot register an nftables input chain inside a container." >&2
    echo "Part 2C needs one. The nf_tables and nft_chain_filter modules must be" >&2
    echo "loaded on the host; any machine already running Docker networking" >&2
    echo "normally has them." >&2
    exit 1
fi

# Every container is given an explicit command so the base image's default CMD
# (sshd -D -e) does not run: no machine in this lab runs sshd, and a stray
# listener on 22 has nothing to do with the lab.
IDLE_CMD=(sleep infinity)

# --init everywhere: PID 1 is `sleep infinity`, which never reaps, and mariadbd,
# lighttpd and every php-cgi it starts all fork children. ip_forward is
# explicitly off on all three: nothing in this lab is a router.
for h in "${HOSTS[@]}"; do
    ctn="$( ctn_of "$h" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 "${PING_SYSCTL[@]}" \
        --hostname "$h" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# The switch. --cap-add=ALL minus SYS_RESOURCE is what the mini-internet's own
# switch containers run with; ovs-vswitchd needs most of it, and SYS_RESOURCE is
# dropped because raising RLIMIT_MEMLOCK is what fails in a user namespace.
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

log "waiting for Open vSwitch in $SW_CTN"
for _ in $(seq 1 60); do
    if docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1; then break; fi
    sleep 0.5
done
docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1 || {
    echo "Open vSwitch did not come up in $SW_CTN" >&2; exit 1; }

log "creating bridge $BR in $SW_CTN"
docker exec "$SW_CTN" ovs-vsctl --may-exist add-br "$BR" >/dev/null
docker exec "$SW_CTN" ovs-vsctl set bridge "$BR" stp_enable=false >/dev/null

# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else.
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

wire_to_switch() {   # <container> <interface inside it> <switch port name>
    i=$(( i + 1 ))
    local ta="vc${i}a" tb="vc${i}b" pid
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    pid="$( docker inspect -f '{{.State.Pid}}' "$SW_CTN" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$3"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$3" up
    docker exec "$SW_CTN" ovs-vsctl add-port "$BR" "$3" >/dev/null
}

for h in "${HOSTS[@]}"; do
    log "wiring $( ctn_of "$h" )($LAN_IF) -> $SW_CTN port $( sw_port_of "$h" )"
    wire_to_switch "$( ctn_of "$h" )" "$LAN_IF" "$( sw_port_of "$h" )"
done

# Apply the per-device starter configs in lib.sh order: the database first, so
# the web server's own start-up has something to connect to.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. Check it with:  $LAB_DIR/scripts/status.sh"
