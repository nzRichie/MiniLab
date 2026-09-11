#!/usr/bin/env bash
# Spawn the addressing-and-static-routing lab: three switched subnets, two Linux
# routers between them, six hosts. Self-contained — drives docker + the veth/OVS
# primitives directly, WITHOUT the full platform/startup.sh pipeline (proposal RQ1).
#
#   west-1 --+                            +-- mid-1          +-- east-1
#            +-- S-WEST -- west-router --+                    |
#   west-2 --+                           +-- S-MID -- east-router -- S-EAST --+
#                                        +-- mid-2                        east-2
#
# Everything arrives unconfigured on purpose. Each device's lab-facing interface
# exists and is wired to the right switch, but it carries no address and is
# administratively DOWN; no host has a default route and neither router has a
# static one. Building all of that is the lab.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

# Open vSwitch is NOT required on the host: every ovs-vsctl call in this lab runs
# inside a switch container, whose image ships OVS. Docker reachability is the
# real prerequisite, and it covers an unreachable daemon as well as a stopped one.
command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and can this account reach it? (try: docker info)" >&2
    exit 1
}

if docker ps -a --format '{{.Names}}' | grep -qx "$( ctn_of "$SW_WEST" )"; then
    echo "Lab already spawned ($( ctn_of "$SW_WEST" ) exists). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# Every lab container is given an explicit command, which is what stops the base
# image's default CMD (sshd -D -e) from running and putting an SSH service on
# every host in a lab that places none.
IDLE_CMD=(sleep infinity)

# 1. The three switches, one per subnet.
for s in "${SWITCHES[@]}"; do
    log "starting switch $( ctn_of "$s" )"
    docker run -d --name "$( ctn_of "$s" )" --network=none \
        --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$s" \
        "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null
done

# 2. The six hosts.
#
# accept_redirects is set here rather than left to chance because the lab's last
# section is built on it. A host applies an ICMP redirect only when it is not
# forwarding and accept_redirects is 1; both are the kernel's defaults for a
# host, and stating them at creation keeps the section from depending on whatever
# the machine running the lab happens to ship. The kernel takes the larger of
# conf.all and the per-interface value, and a per-interface value is copied from
# conf.default when the interface appears, so both have to be set.
#
# ip_forward is deliberately absent: a host is not a router, and leaving it at 0
# is also what makes the host eligible to apply a redirect at all.
#
# ping_group_range is pinned so that ping behaves the same on a rootful and a
# rootless daemon. iputils ping opens a datagram ICMP socket when the caller's
# group is inside this range and falls back to a raw socket when it is not, and
# the two paths print different things: the raw path prints
# "From 192.168.2.2: icmp_seq=1 Redirect Host(...)" with a colon and counts the
# redirect as a delivered packet, while the datagram path prints the same line
# without the colon and reports it as "+1 errors" in the statistics. A rootful
# daemon ships the range as 0 2147483647 and a rootless one as 65534 65534, so
# without this the handout would quote a line half the class does not see.
# "0 0" is the value that works in both: it covers the container's root group,
# which every lab process runs as, and it stays inside the gid map a user
# namespace allows (0 2147483647 is rejected outright under rootless).
for h in "${HOSTS[@]}"; do
    log "starting host $( ctn_of "$h" )"
    docker run -d --name "$( ctn_of "$h" )" --network=none \
        --cap-add=NET_ADMIN --hostname "$h" \
        --sysctl net.ipv4.conf.all.accept_redirects=1 \
        --sysctl net.ipv4.conf.default.accept_redirects=1 \
        --sysctl "net.ipv4.ping_group_range=0 0" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# 3. The two routers.
#
# ip_forward and send_redirects are set at creation rather than by
# default_config/, because Docker mounts /proc/sys read-only in an unprivileged
# container and making a router privileged just to write two values is more
# privilege than this lab needs. The handout says so, so that a learner who tries
# `sysctl -w` and is refused knows why.
#
# send_redirects=1 is the kernel default and is what makes a router tell a sender
# about a better first hop when it forwards a packet back out of the interface it
# arrived on. Middle Net is the only place in this lab where that happens.
for r in "${ROUTERS[@]}"; do
    log "starting router $( ctn_of "$r" ) (forwarding on, redirects on)"
    docker run -d --name "$( ctn_of "$r" )" --network=none \
        --cap-add=NET_ADMIN --hostname "$r" \
        --sysctl net.ipv4.ip_forward=1 \
        --sysctl net.ipv4.conf.all.send_redirects=1 \
        --sysctl net.ipv4.conf.default.send_redirects=1 \
        --sysctl "net.ipv4.ping_group_range=0 0" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# 4. One OVS bridge per switch. Each is a separate container and a separate
#    broadcast domain, so STP stays OFF: there is no loop anywhere in the lab,
#    and STP would hold every port in listening/learning for 15-30 s and delay
#    the learner's first ping.
for s in "${SWITCHES[@]}"; do
    ctn="$( ctn_of "$s" )"
    log "waiting for Open vSwitch in $ctn"
    for _ in $(seq 1 40); do
        if docker exec "$ctn" ovs-vsctl show >/dev/null 2>&1; then break; fi
        sleep 0.5
    done
    log "creating bridge br0 in $ctn"
    docker exec "$ctn" ovs-vsctl \
        -- add-br br0 \
        -- set bridge br0 stp_enable=false \
        -- set-fail-mode br0 standalone >/dev/null
done

# The veth/namespace plumbing runs in a privileged helper container rather than
# on the host, so the learner needs docker access and nothing else. helper_stop
# is trapped so the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0

# 5. Wire each of the ten interfaces to its switch.
#
#    The device end is renamed and left DOWN with no address: that is the state
#    the lab starts from, and `ip link set <if> up` is the learner's own first
#    command on every device. The switch end is brought up and added to br0,
#    because the switch is not what the lab is about and a learner has no reason
#    to configure one.
wire_to_switch() {   # <device> <interface> <switch>
    local dev="$1" dev_if="$2" sw="$3"
    local ctn sw_ctn port pid spid ta tb
    ctn="$( ctn_of "$dev" )"
    sw_ctn="$( ctn_of "$sw" )"
    port="$( sw_port_of "$dev" )"
    i=$((i + 1))
    ta="vn${i}a"; tb="vn${i}b"

    helper ip link add "$ta" type veth peer name "$tb"

    pid="$( docker inspect -f '{{.State.Pid}}' "$ctn" )"
    helper ip link set "$ta" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$ta" name "$dev_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$dev_if" down

    spid="$( docker inspect -f '{{.State.Pid}}' "$sw_ctn" )"
    helper ip link set "$tb" netns "$spid"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$tb" name "$port"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$port" up
    docker exec "$sw_ctn" ovs-vsctl add-port br0 "$port" >/dev/null
}

for row in "${LINKS[@]}"; do
    set -- $row
    log "wiring $1($2) -> $3 (port $( sw_port_of "$1" ))"
    wire_to_switch "$1" "$2" "$3"
done

# 6. Apply the per-device starter configs. Each one asserts the blank state the
#    lab begins in rather than configuring anything, which is what lets reset.sh
#    re-run them to throw the learner's work away.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    log "applying default_config/${d}.sh to $ctn"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec "$ctn" "/home/${d}.sh"
done

log "lab is up, and nothing in it is configured. Check it with:  $LAB_DIR/scripts/status.sh"
