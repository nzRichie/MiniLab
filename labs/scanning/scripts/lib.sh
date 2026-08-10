#!/usr/bin/env bash
# Shared definitions for the internet-scanning lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, ports, and credentials. Every other script sources it; never
# hardcode any of these in a second place.
#
# The lab is Layer 4: a router separates the attacker from the network it scans,
# and what the learner discovers is which transport ports are open behind that
# router and which service sits on each. The load-bearing facts here are the
# addresses inside the scanned /24 (deliberately scattered, so a sweep is the
# only way to find them) and which of those hosts answers an ICMP echo.

AS=104
DC=LAB
SW=S1

# ---------------------------------------------------------------------------
# Two subnets, one router between them.
#   external : the attacker's own network; it is not part of what it scans
#   target   : the /24 under survey — four hosts inside 254 addresses
# Both live inside the AS's 104.0.0.0/8 block, so subnet_config's AS-octet scheme
# still holds and every address is known before a container exists.
EXT_SUBNET="104.0.0.0/24"    # attacker + router (point-to-point, no switch)
TGT_SUBNET="104.1.0.0/24"    # the scanned network (switched segment)
PREFIXLEN=24

ROUTER_EXT_IP="104.0.0.1"    # router, attacker side (the attacker's default gateway)
ROUTER_TGT_IP="104.1.0.1"    # router, target side   (the target hosts' default gateway)
ATTACKER_IP="104.0.0.10"     # attacker, outside the network it scans

# The four hosts inside the /24. The addresses are scattered across the range on
# purpose: no consecutive block, nothing at a round number, so reading them off a
# sweep is the only way to get them. .1 is the router, and answers as well, which
# is why a sweep of this /24 returns five addresses and not four.
WEB_IP="104.1.0.23"          # HTTP  (lighttpd)
IDLE_IP="104.1.0.42"         # nothing listening; up, and that is all
FTP_IP="104.1.0.87"          # FTP   (vsftpd, anonymous login)
TELNET_IP="104.1.0.201"      # telnet (busybox telnetd) — the password-attack target

# The ports those services listen on. Named here so the handout, the status
# oracle and selftest cannot drift apart on which port belongs to which host.
WEB_PORT=80
FTP_PORT=21
TELNET_PORT=23

# ---------------------------------------------------------------------------
# The one host inside the /24 that does NOT answer an ICMP echo request.
#
# This is the lab's central discovery lesson and it is a deliberate configuration,
# not an accident: default_config/host3.sh installs an iptables rule dropping inbound
# echo-requests. A ping sweep (zmap's icmp_echoscan, or nmap -sn -PE) therefore
# reports four live addresses and misses this one entirely, while an nmap -sn with
# its default probe set finds it, because that set also sends TCP to ports 80 and
# 443 and a live host answers a closed port with a RST. The learner is meant to
# notice the two counts disagree and work out which tool was lying.
ICMP_SILENT_IP="$FTP_IP"

# ---------------------------------------------------------------------------
# Interface names.
#   External point-to-point link (attacker <-> router), no switch:
ATT_IF="${AS}-ext"           # the attacker's only NIC (host-side <AS>-<peer>)
R_EXT_IF="ext"               # router's attacker-facing NIC
#   Target switched segment (router + target hosts <-> S1):
R_TGT_IF="int"               # router's target-facing NIC
HOST_IF="${AS}-${SW}"        # each target host's NIC, named after the switch

# ---------------------------------------------------------------------------
# The credential chain Part 3 turns on.
#
# The anonymous FTP share holds a handover note naming the telnet account, so the
# username is something the learner RECOVERS during enumeration rather than
# something the handout hands over. The password is not written anywhere in the
# lab's content: it is one of the fifty entries in the wordlist baked into the
# image, and hydra is what finds which.
#
# The password is set here because spawn, reset and selftest all need it, and
# default_config/host4.sh needs it to create the account. It is therefore in the
# student tree: this file and default_config/host4.sh both ship, because spawn.sh
# cannot run without them. That is inherent to a self-contained lab whose scenario
# lives in its own configuration, and it is not worth obfuscating; what the lab
# does not do is advertise where in the wordlist it sits. Question 14 is graded on
# the timing and the arithmetic as much as on the word, and every other question
# in Part 3 is unaffected by knowing it.
TELNET_USER="netadmin"
TELNET_PASS="trustno1"
PASS_LIST="/usr/share/minilabs/passwords.txt"     # 50 common passwords, in the image
FTP_LEAK_FILE="handover.txt"                      # what ftp-anon lists on 104.1.0.87
FTP_ROOT="/var/lib/ftp"                           # vsftpd's anonymous root

# ---------------------------------------------------------------------------
SWITCH_IMAGE="miniinterneteth/d_switch"

HOST_IMAGE="d_host_scan"
# Open vSwitch is started explicitly instead of through the image's supervisord
# entrypoint, so that --no-mlockall can be passed. ovs-ctl locks ovs-vswitchd
# into memory by default. Under rootless Docker CAP_IPC_LOCK is confined to the
# user namespace and cannot exceed RLIMIT_MEMLOCK (8 MB on a stock host), so the
# first thread stack past that limit fails to lock and ovs-vswitchd dies with
# "pthread_create failed (Resource temporarily unavailable)". Locking buys this
# lab nothing: a lab switch forwards a handful of packets and never needs its
# pages pinned. Under rootful Docker the resulting datapath is identical.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# Container names follow the platform convention, with L4 marking the lab's layer:
# <AS>_L4_<DC>_<name>. One prefix covers every container (including the switch, an
# L2 device) so status/teardown can select the lab with a single filter.
#
# THE FOUR TARGET HOSTS ARE NAMED host1..host4 AND NOTHING ELSE. Naming them web,
# ftp, telnet and idle put Part 2's answers in the output of `docker ps`, in
# spawn.sh's log lines, and on the switch's port list, so a learner who ran Spawn
# and looked at the panel already knew which services were in the /24 before
# scanning for them. The role each one plays is an authoring detail; it belongs in
# this file's variable names, in default_config/ and in the answer key, not in a
# string the lab prints. Same reason the switch ports are 104-host1..104-host4.
#
#   host1  104.1.0.23   HTTP        host3  104.1.0.87   FTP, silent to ping
#   host2  104.1.0.42   no service  host4  104.1.0.201  telnet
SW_CTN="${AS}_L4_${DC}_${SW}"
ROUTER_CTN="${AS}_L4_${DC}_router"
ATTACKER_CTN="${AS}_L4_${DC}_attacker"
WEB_CTN="${AS}_L4_${DC}_host1"
IDLE_CTN="${AS}_L4_${DC}_host2"
FTP_CTN="${AS}_L4_${DC}_host3"
TELNET_CTN="${AS}_L4_${DC}_host4"

# Target hosts wired to the switch S1 (each takes HOST_IF). The router attaches to
# S1 too, but through R_TGT_IF; spawn handles it separately. These tokens are what
# ctn_of and sw_port_of build names from, and what default_config/<token>.sh is
# called, so they carry no service name for the reason set out above.
TARGET_HOSTS=(host1 host2 host3 host4)

# Every device that gets a starter config, in apply order: the router first so
# forwarding is up before anything crosses it, then the services, attacker last.
DEVICES=(router host1 host2 host3 host4 attacker)

# The address of each target host, keyed by token. Used by topology.sh, status.sh
# and selftest.sh so none of them repeats an address literal.
declare -A TARGET_IP=(
    [host1]="$WEB_IP" [host2]="$IDLE_IP" [host3]="$FTP_IP" [host4]="$TELNET_IP"
)

ctn_of()     { echo "${AS}_L4_${DC}_$1"; }
sw_port_of() { echo "${AS}-$1"; }

# The kernel hostname each container boots with. It is NOT the container name for
# the telnet host, for two reasons.
#
# The prompt is the visible one: image/lab-login prints "<hostname> login: ", so
# the hostname is what a learner reads when they finally get a session, and the
# handover note they recovered calls that box a switch. TELNET_HOSTNAME makes the
# prompt say so.
#
# The other reason is that this hostname is inside the bytes nmap -sV probes read
# back, and one of nmap's own signatures (`match landesk-rc m=^(?!HTTP|RTSP|SIP)
# .{264}$=s`) matches on nothing but a 264-byte reply. Naming the container host4
# put a reply on exactly 264 bytes, so -sV stopped printing the service
# fingerprint the handout has the learner read and confidently reported "LANDesk
# remote management" instead. Pinning the prompt here keeps the reply length off
# that boundary and out of the reach of a later container rename;
# selftest.sh's telnet_sv_prints_service_fingerprint check is what catches it if
# some future edit lands on 264 again.
TELNET_HOSTNAME="kfl-sw1"    # the switch the handover note names, at 104.1.0.201
hostname_of() { case "$1" in telnet|host4) echo "$TELNET_HOSTNAME" ;; *) echo "$1" ;; esac; }

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. Without this
# an image is only rebuilt when it is MISSING, which means an edit to image/ never
# reaches a machine that built the image once: the container keeps running the
# previous version and the handout describes tooling the learner does not have.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

# Image preflight, called by spawn.sh before the first `docker run`.
# The switch image is upstream and pulled; the host image is this lab's own and
# built from image/. Docker caches both, so every spawn after the first is a
# no-op here unless image/ has changed.
ensure_images() {
    if ! docker image inspect "$SWITCH_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] pulling $SWITCH_IMAGE (first run only)"
        docker pull "$SWITCH_IMAGE" >/dev/null \
            || { echo "failed to pull $SWITCH_IMAGE" >&2; return 1; }
    fi
    if ! docker image inspect "$HOST_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] building $HOST_IMAGE from $LAB_DIR/image (first run only)"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to build $HOST_IMAGE" >&2; return 1; }
    elif image_older_than_source "$HOST_IMAGE" "$LAB_DIR/image"; then
        echo "[spawn] rebuilding $HOST_IMAGE: $LAB_DIR/image changed since it was built"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to rebuild $HOST_IMAGE" >&2; return 1; }
    fi
}

# ---------------------------------------------------------------------------
# Privileged host networking, performed from a helper container.
#
# Wiring a lab needs privileges a learner's account will not have: CAP_NET_ADMIN
# to create a veth pair, and CAP_SYS_ADMIN to enter a container's network
# namespace and rename the interface inside it. Rather than require root on the
# host, a throwaway --privileged container holds them.
#
# The helper keeps a network namespace of its own (--network=none). Both ends of
# every veth pair are moved out into lab containers, so the namespace the pair is
# created in never matters. Asking for the host's namespace (--network=host)
# only breaks the helper under a rootless daemon, where that namespace belongs to
# a user namespace the helper holds no privilege in and every `ip link add`
# returns EPERM. --pid=host stays: it is what makes each lab container's
# /proc/<pid>/ns/net reachable for the moves.
#
# Renames run through `nsenter --net`, not `ip netns exec`. iproute2 remounts
# /sys on every namespace switch and a user namespace forbids that, while the
# rename itself is pure netlink and needs no sysfs at all.
#
# The kernel objects are identical to the host-root path: same veth pair, same
# namespaces, same interface names, same OVS ports. Only the identity of the
# process issuing the netlink calls changes, which nothing in the data plane can
# observe. Docker access is the only privilege a learner needs, and on a rootless
# daemon that access no longer carries root on the host.
HELPER_CTN="$( ctn_of netadmin_helper )"

# Start the helper and wait until it can run a command. `--rm` plus a bounded
# sleep means an interrupted spawn cannot leave it running forever; spawn also
# stops it explicitly through an EXIT trap.
helper_start() {
    docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true
    docker run -d --rm --name "$HELPER_CTN" \
        --privileged --network=none --pid=host \
        "$HOST_IMAGE" sleep 600 >/dev/null
    for _ in $(seq 1 40); do
        if docker exec "$HELPER_CTN" true >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    echo "helper container $HELPER_CTN did not become ready" >&2
    return 1
}

# Run one privileged networking command inside the helper.
helper() { docker exec "$HELPER_CTN" "$@"; }


helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }
