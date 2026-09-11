#!/usr/bin/env bash
# Spawn the stack overflow and build-hardening lab: the appliance, the
# operator's workstation and the attacker's machine on one switched segment.
# Self-contained -- drives docker + the veth primitives directly, WITHOUT the
# full platform/startup.sh pipeline.
#
#   svc ------\
#   ops -------[ S1 ]
#   attacker -/
#
# One segment and no router. The bug is in a program rather than in the network,
# and every stage of Part 2 is enforced inside the appliance, so a second
# segment would add a boundary nothing in the lab is measured on.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and can this account reach it? (try: docker info)" >&2
    exit 1
}

# Offsets and addresses do not survive a change of instruction set, so the lab
# refuses to run where its own handout would be wrong rather than producing a
# binary the learner cannot follow.
arch="$( uname -m )"
if [ "$arch" != "x86_64" ]; then
    echo "this lab is x86-64 only; this machine reports '$arch'." >&2
    echo "Every address, offset and instruction the handout quotes is a fact about" >&2
    echo "x86-64 code, and none of them survive the move to another architecture." >&2
    exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$SVC_CTN"; then
    echo "Lab already spawned ($SVC_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# Part 2C turns randomisation off for the service process with `setarch -R`,
# which calls personality(ADDR_NO_RANDOMIZE). Docker's default seccomp profile
# does not allow that argument value, so the appliance runs with seccomp
# unconfined. Prove it works here, with the reason, rather than halfway through
# Part 2C with an EPERM the learner would read as their own mistake.
log "checking this host can clear address-space randomisation inside a container"
if ! docker run --rm "${SVC_SECURITY_OPT[@]}" "$HOST_IMAGE" \
        setarch -R true >/dev/null 2>&1; then
    echo "this host cannot run 'setarch -R' inside a container even with seccomp" >&2
    echo "unconfined. Part 2C needs it: it is how address-space randomisation is" >&2
    echo "turned off for one process instead of for the whole machine." >&2
    exit 1
fi

# Every container is given an explicit command so the base image's default CMD
# does not run. --init because PID 1 is `sleep infinity`, which never reaps, and
# the service forks a child per connection.
IDLE_CMD=(sleep infinity)

log "starting appliance $SVC_CTN (seccomp unconfined, so setarch -R works)"
docker run -d --name "$SVC_CTN" --network=none --init \
    --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=0 "${PING_SYSCTL[@]}" \
    "${SVC_SECURITY_OPT[@]}" \
    --hostname svc \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

for h in ops attacker; do
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
    local ta="vs${i}a" tb="vs${i}b" pid
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

# Apply the per-device starter configs in lib.sh order.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. Check it with:  $LAB_DIR/scripts/status.sh"
