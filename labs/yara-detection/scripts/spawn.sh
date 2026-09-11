#!/usr/bin/env bash
# Spawn the YARA rule authoring and generalisation lab: four hosts on one
# segment behind one switch. Self-contained -- drives docker + the veth
# primitives directly, WITHOUT the full platform/startup.sh pipeline (RQ1).
#
#   workstation --\                 /-- client
#                  [ S1 ] ---------
#   scanner ------/                 \-- holdout
#
# The workstation holds the corpus and is where every rule is written. The
# scanner runs the upload endpoint Part 4 deploys to. The client posts the two
# files to it. The holdout holds the ten files Part 3 is scored against and runs
# nothing: status.sh copies the learner's rule file in and runs yara there,
# which is the only traffic it ever sees.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$WORKSTATION_CTN"; then
    echo "Lab already spawned ($WORKSTATION_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# Every container is given an explicit command, which is what stops an image's
# default CMD from running.
IDLE_CMD=(sleep infinity)

# --init everywhere. PID 1 would otherwise be `sleep infinity`, which never
# calls wait(). The scanner forks a CGI and a clamscan per upload and the
# workstation forks a yara per sample, and without docker-init they accumulate
# as zombies for as long as the lab is up.
#
# ip_forward is set explicitly to 0 on every host: nothing in this lab forwards,
# and a reader of this file should not have to know what the default is to find
# that out. It is set at creation because Docker mounts /proc/sys read-only in
# an unprivileged container.
for role in workstation scanner client; do
    ctn="$( ctn_of "$role" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 \
        --hostname "$role" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

log "starting $HOLDOUT_CTN (the scoring appliance; no service listens on it)"
docker run -d --name "$HOLDOUT_CTN" --network=none --init \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 \
    --hostname holdout \
    "$HOLDOUT_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# The switch. --cap-add=ALL minus SYS_RESOURCE is what the mini-internet's own
# switch containers run with; ovs-vswitchd needs most of it, and SYS_RESOURCE is
# dropped because raising RLIMIT_MEMLOCK is exactly what fails in a user
# namespace.
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname S1 \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

log "waiting for Open vSwitch in $SW_CTN"
for _ in $(seq 1 60); do
    if docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1; then break; fi
    sleep 0.5
done
docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1 || {
    echo "Open vSwitch did not come up in $SW_CTN" >&2; exit 1; }

# One flat broadcast domain, no STP and no VLANs: the switch is not what this
# lab is about.
log "creating bridge $BR in $SW_CTN"
docker exec "$SW_CTN" ovs-vsctl --may-exist add-br "$BR" >/dev/null
docker exec "$SW_CTN" ovs-vsctl set bridge "$BR" stp_enable=false >/dev/null

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

wire_to_switch() {   # <container> <interface inside it> <switch port name>
    i=$(( i + 1 ))
    local ta="vi${i}a" tb="vi${i}b" pid
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    pid="$( docker inspect -f '{{.State.Pid}}' "$SW_CTN" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$3"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$3" up
    docker exec "$SW_CTN" ovs-vsctl add-port "$BR" "$3" >/dev/null
}

for role in workstation scanner client holdout; do
    ctn="$( ctn_of "$role" )"
    log "wiring $ctn($LAN_IF) -> $SW_CTN port $( sw_port_of "$role" )"
    wire_to_switch "$ctn" "$LAN_IF" "$( sw_port_of "$role" )"
done

# Apply the per-device starter configs in the order lib.sh defines.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. Thirty samples under $CORPUS_DIR on the workstation, no rule file yet."
log "Check it with:  $LAB_DIR/scripts/status.sh"
