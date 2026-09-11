#!/usr/bin/env bash
# Spawn the centralised logging lab: four machines on one switched segment.
# Self-contained — drives docker + the veth/OVS primitives directly, WITHOUT the
# full platform/startup.sh pipeline (proposal RQ1).
#
#   collector --+
#   admin     --+-- S1
#   web       --+
#   db        --+
#
# One segment and no router, because nothing in this lab is about reaching
# somewhere: a message that does not arrive at the collector failed for a reason
# in the logging configuration, never for a reason in the network.
#
# Everything except the logging arrives configured: addresses are up, rsyslog
# runs on all four, sshd runs on the two machines that accept logins and lighttpd
# runs on the web service. Each of the three source machines writes what it
# produces to a file on its own disk and sends it nowhere, and the collector
# listens on no port. Every rule that changes that is the learner's to write.
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

if docker ps -a --format '{{.Names}}' | grep -qx "$COLLECTOR_CTN"; then
    echo "Lab already spawned ($COLLECTOR_CTN exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# Every lab container is given an explicit command, which is what stops the base
# image's default CMD (sshd -D -e) from running. That default matters more here
# than in most labs: it starts sshd with -e, which sends its output to standard
# error instead of to syslog, and every authentication line the lab reconstructs
# from would go to the container's console where no forwarding rule can reach it.
# The two machines that need sshd start it from their starter config instead,
# without -e.
IDLE_CMD=(sleep infinity)

# ping_group_range is pinned so that ping prints the same thing on a rootful and
# a rootless daemon. iputils ping opens a datagram ICMP socket when the caller's
# group is inside this range and falls back to a raw socket when it is not, and
# the two paths report an unanswered request differently. A rootful daemon ships
# the range as 0 2147483647 and a rootless one as 65534 65534.
PING_SYSCTL=(--sysctl "net.ipv4.ping_group_range=0 0")

# The switch.
log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

# The four end hosts.
#
# --hostname is load-bearing on every one of them, and not cosmetic. The HOSTNAME
# field of a syslog message is filled in from it, that field is what the
# collector's per-host template keys the destination file on, and a container
# left with its default hostname would file its messages under a twelve-digit
# container id that changes on every spawn.
#
# --init on all four. Their PID 1 would otherwise be `sleep infinity`, which
# never calls wait(), so every rsyslogd, sshd and lighttpd child that exits stays
# in the process table as a zombie and the `pkill -x` in reset.sh starts matching
# dead processes.
#
# NET_ADMIN is what lets the starter configs address the interface without the
# container being privileged.
for h in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$h" )"
    log "starting $ctn"
    docker run -d --name "$ctn" --network=none --init \
        --cap-add=NET_ADMIN --hostname "$h" \
        "${PING_SYSCTL[@]}" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# The segment's bridge. STP stays OFF: there is no loop anywhere in this lab, and
# STP would hold every port in listening/learning for 15 to 30 seconds and delay
# the learner's first message for no reason.
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

# Wire a device into the bridge. The switch end is brought up and added to br0;
# the switch is not what this lab is about and a learner has no reason to
# configure one.
wire_to_switch() {   # <device>
    local dev="$1" port pid ta tb
    port="$( sw_port_of "$dev" )"
    i=$(( i + 1 )); ta="vn${i}a"; tb="vn${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$( ctn_of "$dev" )" "$HOST_IF" "$ta"
    pid="$( docker inspect -f '{{.State.Pid}}' "$SW_CTN" )"
    helper ip link set "$tb" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tb" name "$port"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$port" up
    docker exec "$SW_CTN" ovs-vsctl add-port br0 "$port" >/dev/null
}

for h in "${DEVICES[@]}"; do
    log "wiring $( ctn_of "$h" )($HOST_IF) -> $SW_CTN port $( sw_port_of "$h" )"
    wire_to_switch "$h"
done

# Apply the per-device starter configs. The collector goes first, because it is
# the machine the other three will eventually be pointed at, and because a spawn
# that fails half way is easier to read when the failure is on the machine whose
# turn it was.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "configuring $ctn via default_config/${d}.sh"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up. Each machine logs to its own disk; the collector receives nothing."
log "Check it with:  $LAB_DIR/scripts/status.sh"
