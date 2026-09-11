#!/usr/bin/env bash
# Shared definitions for the firewalling and intrusion detection lab.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, interface names, service ports, credentials and file paths. Every
# other script sources it; never hardcode any of these in a second place.
#
# The lab is played attacker first, defender second, on one topology. An outside
# machine scans a server, reaches its telnet service and logs in. The learner
# then writes the server's own packet filter, then a set of Suricata signatures
# that record what the filter would only have counted, then puts Suricata inline
# so the same signatures drop the packets they match. The graded end state is
# measured by three facts at once: the outside machine no longer reaches tcp/23,
# the inside machine still does, and the public web site still answers from
# outside.

AS=124
DC=LAB

# ---------------------------------------------------------------------------
# Two segments meeting at a router.
#
#   inside  : the server and one internal workstation, over a switch.
#   outside : the attacker and one legitimate outside customer, over a switch
#             of their own.
#
# The router FORWARDS (net.ipv4.ip_forward is 1) and does not translate
# addresses. Every packet that crosses it still carries its original source
# address, which is what makes a source-address match on the server mean
# anything at all. Behind a NAT every outside packet would arrive with the
# router's address and Part 1 would have nothing to match on.
INSIDE_SUBNET="124.0.0.0/24"
OUTSIDE_SUBNET="124.1.0.0/24"

# The second outside prefix. It is on the SAME physical segment as
# OUTSIDE_SUBNET: the router's outside interface carries an address in each, and
# the attacker's machine does too. That is what Part 1's fourth step turns on.
# A rule written against one outside prefix is not a rule against the attacker,
# and the cheapest way to show it is an attacker who already holds an address
# the rule does not name.
OUTSIDE_ALT_SUBNET="124.9.0.0/24"
PREFIXLEN=24

RTR_INSIDE_IP="124.0.0.1"
RTR_OUTSIDE_IP="124.1.0.1"
RTR_OUTSIDE_ALT_IP="124.9.0.1"

SERVER_IP="124.0.0.10"
CLIENT_IP="124.0.0.20"

ATTACKER_IP="124.1.0.66"        # the address every capture in Part 1 shows first
ATTACKER_ALT_IP="124.9.0.66"    # the second address, on the second outside prefix
CUSTOMER_IP="124.1.0.77"        # a legitimate outside reader of the public web site

# ---------------------------------------------------------------------------
# What the server runs. Three listeners, and which of the three is the exposure
# is the whole of Part 1: ssh authenticates over an encrypted channel, the web
# site is meant to be public, and telnet is neither.
SSH_PORT=22
TELNET_PORT=23
HTTP_PORT=80

# The account the attacker reaches. It is unprivileged on purpose: the lab is
# about what a filter and a signature can reach, not about privilege escalation,
# and a shell as a service account is already the compromise the lab is written
# around.
LOGIN_USER="svcops"
LOGIN_PASS="labpass"

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<segment>
# convention, so the two machines on a segment share an interface name and what
# distinguishes them at the switch is the port name below. The router names each
# of its two NICs after the segment it faces.
#
# The server's interface name is quoted verbatim in the handout, in the tcpdump
# command, the iptables -i match and the suricata -i argument. It is one string
# in one place here for that reason.
LAN_IF="${AS}-lan"
EXT_IF="${AS}-ext"
RTR_INSIDE_IF="lan"
RTR_OUTSIDE_IF="ext"

# One switch per segment rather than two bridges in one switch container. Two
# bridges in one Open vSwitch instance would behave identically, and would draw
# as a single box that every machine in the lab connects to. The fact this lab
# rests on is that the only path from outside to the server is through the
# router, and a figure that appears to contradict it is worse than one more
# container.
SW_IN="S1"
SW_OUT="S2"
SW_IN_CTN="${AS}_L4_${DC}_${SW_IN}"
SW_OUT_CTN="${AS}_L4_${DC}_${SW_OUT}"
SWITCHES=(S1 S2)
BR="br0"
sw_port_of() { echo "${AS}-$1"; }        # 124-server, 124-attacker, ...

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L4 marking the lab's
# layer: <AS>_L4_<DC>_<name>. Every rule the learner writes matches on an IP
# address, an IP protocol number or a TCP port, which is where this lab sits.
SERVER_CTN="${AS}_L4_${DC}_server"
CLIENT_CTN="${AS}_L4_${DC}_client"
RTR_CTN="${AS}_L4_${DC}_router"
ATTACKER_CTN="${AS}_L4_${DC}_attacker"
CUSTOMER_CTN="${AS}_L4_${DC}_customer"

ctn_of() { echo "${AS}_L4_${DC}_$1"; }

# Every device that gets a starter config, in apply order: the router first so
# there is a path between the segments, then the server whose services the rest
# of the lab aims at, then the two clients.
DEVICES=(router server client attacker customer)

ip_of() {   # <role> -> the address the handout names it by
    case "$1" in
        router)   echo "$RTR_INSIDE_IP" ;;
        server)   echo "$SERVER_IP" ;;
        client)   echo "$CLIENT_IP" ;;
        attacker) echo "$ATTACKER_IP" ;;
        customer) echo "$CUSTOMER_IP" ;;
        *)        echo "" ;;
    esac
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_ids"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed". --no-mlockall is what
# makes this lab boot on a rootless daemon.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# Suricata's files on the server.
#
# SURICATA_YAML is edited twice by the learner: once to add the local rules file
# to rule-files, and once to uncomment the nfq block. reset.sh restores it from
# SURICATA_YAML_PRISTINE, a copy the image takes before anything has touched it,
# because a sed applied twice to a file somebody else has already edited is how
# a reset leaves a machine in a state neither the handout nor the key describes.
SURICATA_DIR="/etc/suricata"
SURICATA_YAML="${SURICATA_DIR}/suricata.yaml"
SURICATA_YAML_PRISTINE="/usr/local/share/minilabs/suricata.yaml.orig"
LOCAL_RULES="${SURICATA_DIR}/rules/local.rules"
SURICATA_LOG_DIR="/var/log/suricata"
FAST_LOG="${SURICATA_LOG_DIR}/fast.log"
SURICATA_STDOUT="${SURICATA_LOG_DIR}/stdout.log"

# The two signature identifiers the lab uses. Both are inside the range
# 1000000-1999999, which Suricata reserves for locally written rules.
SID_INTERNAL=1000001
SID_EXTERNAL=1000002

# The NFQUEUE queue number Part 3 uses. One queue, number 0, named in the
# iptables rule and in suricata's -q argument; they have to agree.
NFQUEUE_NUM=0

# ---------------------------------------------------------------------------
# How long Suricata takes to be ready.
#
# The Alpine package ships a rule set of about fifty thousand signatures in
# /var/lib/suricata/rules/suricata.rules, and Suricata parses and compiles all
# of them before it reads its first packet. On the machines this lab is built
# for that is twenty to thirty seconds, every start and every reload. Nothing
# waits on a fixed sleep anywhere in this lab: everything waits on the line
# Suricata prints when it is actually ready.
SURICATA_READY_MARK="Engine started"
SURICATA_READY_TIMEOUT=120

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# otherwise only rebuilt when it is missing, which means an edit to
# image/Dockerfile never reaches a machine that built the image once: the
# container keeps running the previous version and the handout describes tooling
# the learner does not have.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

ensure_images() {
    if ! docker image inspect "$HOST_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] building $HOST_IMAGE from $LAB_DIR/image (first run only)"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to build $HOST_IMAGE" >&2; return 1; }
    elif image_older_than_source "$HOST_IMAGE" "$LAB_DIR/image"; then
        echo "[spawn] rebuilding $HOST_IMAGE: $LAB_DIR/image changed since it was built"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to rebuild $HOST_IMAGE" >&2; return 1; }
    fi
    if ! docker image inspect "$SWITCH_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] pulling $SWITCH_IMAGE (first run only)"
        docker pull "$SWITCH_IMAGE" >/dev/null \
            || { echo "failed to pull $SWITCH_IMAGE" >&2; return 1; }
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
HELPER_CTN="$( ctn_of netadmin_helper )"

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

helper() { docker exec "$HELPER_CTN" "$@"; }

helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }

# ---------------------------------------------------------------------------
# Shared read-only probes. status.sh and selftest.sh both need these, and a
# second copy of any of them is a chance for the two to disagree about what the
# lab's success condition is.

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# --- reaching the server ---------------------------------------------------

# Does a TCP SYN from <role> to <port> on the server get a SYN-ACK back?
#
# nping is the measurement rather than a connect(), because a connect() cannot
# tell a filtered port from a closed one without a timeout, and because it is
# the tool the handout puts in the learner's hands. `--flags syn` sends the same
# packet the handout sends; RCVD lines carrying SA are the replies.
#
# -S names the source address explicitly so the attacker's two addresses can be
# probed one at a time. nping needs --send-eth with a spoofed-looking source
# under some setups; both of these addresses are real addresses of the machine
# sending, so the ordinary path works.
syn_reaches() {   # <role> <port> [source address]
    local role="$1" port="$2" src="${3:-}"
    local ctn out
    ctn="$( ctn_of "$role" )"
    if [ -n "$src" ]; then
        out="$( docker exec "$ctn" nping --tcp -p "$port" --flags syn -c 3 \
                   --delay 300ms -S "$src" "$SERVER_IP" 2>/dev/null )"
    else
        out="$( docker exec "$ctn" nping --tcp -p "$port" --flags syn -c 3 \
                   --delay 300ms "$SERVER_IP" 2>/dev/null )"
    fi
    grep -qa 'RCVD.*SA ' <<< "$out"
}

# The HTTP status code <role> gets from the server's web site, or 000 when the
# transfer never produced a status line, which is what a dropped packet looks
# like to a client once curl runs out of patience.
#
# The output is captured and inspected rather than guarded with `|| echo 000`:
# curl WRITES its -w line even when the transfer failed and then exits non-zero,
# so a fallback fires on top of a value curl has already printed. A code is
# three digits or it is not a code.
http_code() {   # <role>
    local out
    out="$( docker exec "$( ctn_of "$1" )" curl -s -o /dev/null -m 8 \
               -w '%{http_code}' "http://${SERVER_IP}/" 2>/dev/null )"
    case "$out" in
        [0-9][0-9][0-9]) echo "$out" ;;
        *)               echo 000 ;;
    esac
}

# A scripted telnet login from <role>, ending in a command whose output is a
# marker. Returns 0 when the marker came back, which means the whole exchange
# completed: the SYN reached tcp/23, the service answered, login accepted the
# password, and a shell ran a command.
#
# The session is filtered down to printable ASCII before it is searched, and the
# search runs with grep -a. Telnet begins with option negotiation, so the first
# bytes of every session are 0xff 0xfd 0x01 and the like; a grep handed those
# bytes decides the input is binary and, in ugrep, reports no match even when
# the marker is plainly there. The oracle then says the attacker never got in.
#
# The waits are what make it work at all. busybox telnetd runs /bin/login, and
# login reads the username and the password from a terminal one at a time; a
# heredoc that writes both at once arrives before either prompt and is
# discarded. Each write is therefore preceded by a sleep long enough for the
# prompt it answers, and nc's own idle timeout is longer than all of them
# together.
telnet_login() {   # <role>
    local ctn out
    ctn="$( ctn_of "$1" )"
    out="$( docker exec "$ctn" sh -c "
        { sleep 1; printf '${LOGIN_USER}\r\n'
          sleep 2; printf '${LOGIN_PASS}\r\n'
          sleep 3; printf 'echo MINILABS-SHELL-OK\r\n'
          sleep 2; } | nc -w 14 ${SERVER_IP} ${TELNET_PORT} 2>/dev/null | tr -cd '\11\12\15\40-\176'
        " 2>/dev/null )"
    grep -qa 'MINILABS-SHELL-OK' <<< "$out"
}

# --- what the server is configured to do -----------------------------------

# The INPUT chain of the filter table, with counters and rule numbers, exactly
# as the handout has the learner read it.
iptables_input() {
    docker exec "$SERVER_CTN" iptables -L INPUT -n -v --line-numbers 2>/dev/null
}

# The number of rules in the INPUT chain. Two header lines precede them.
iptables_rule_count() {
    docker exec "$SERVER_CTN" sh -c \
        "iptables -S INPUT 2>/dev/null | grep -c '^-A'" 2>/dev/null | tr -dc '0-9'
}

# The packet counter on the rule at <n> in the INPUT chain, or "" when there is
# no such rule.
iptables_pkts_at() {   # <rule number>
    docker exec "$SERVER_CTN" sh -c \
        "iptables -L INPUT -n -v -x --line-numbers 2>/dev/null | awk '\$1 == $1 { print \$2 }'"
}

# True when the INPUT chain sends packets arriving on the server's own interface
# to a netfilter queue, which is what puts Suricata inline.
nfqueue_rule_present() {
    docker exec "$SERVER_CTN" sh -c \
        "iptables -S INPUT 2>/dev/null | grep -q 'NFQUEUE'"
}

# --- Suricata --------------------------------------------------------------

suricata_running() {
    docker exec "$SERVER_CTN" sh -c 'pgrep -x suricata >/dev/null 2>&1'
}

# "ids", "ips" or "" -- read from the command line Suricata was started with.
# `-q` means it is taking packets from a netfilter queue and issuing a verdict
# on each one; `-i` means it is reading copies off an interface and can only
# record what it saw.
suricata_mode() {
    local cmd
    cmd="$( docker exec "$SERVER_CTN" sh -c \
        "tr '\\0' ' ' < /proc/\$(pgrep -x suricata | head -1)/cmdline 2>/dev/null" )"
    case " $cmd " in
        *" -q "*) echo ips ;;
        *" -i "*) echo ids ;;
        *)        echo "" ;;
    esac
}

# True once Suricata has finished compiling its rules and is reading packets.
suricata_ready() {
    docker exec "$SERVER_CTN" sh -c \
        "grep -q '$SURICATA_READY_MARK' '$SURICATA_STDOUT' 2>/dev/null"
}

# Block until Suricata is ready, or give up. Returns non-zero on the timeout so
# a caller can say so rather than going on to measure a Suricata that is still
# loading and reporting that nothing was detected.
suricata_await_ready() {   # [seconds]
    local limit="${1:-$SURICATA_READY_TIMEOUT}" i=0
    while [ "$i" -lt $(( limit * 2 )) ]; do
        suricata_ready && return 0
        i=$(( i + 1 )); sleep 0.5
    done
    return 1
}

# How many rules Suricata loaded, from the line it prints at startup.
suricata_rules_loaded() {
    docker exec "$SERVER_CTN" sh -c \
        "grep -o '[0-9]* rules successfully loaded' '$SURICATA_STDOUT' 2>/dev/null | tail -1 | cut -d' ' -f1"
}

# Alert lines in fast.log carrying <sid>. The sid sits in the [1:<sid>:<rev>]
# field, so the pattern is anchored on both colons and cannot match a port
# number or an address that happens to contain the same digits.
alerts_for_sid() {   # <sid>
    docker exec "$SERVER_CTN" sh -c \
        "grep -c '\[1:$1:' '$FAST_LOG' 2>/dev/null" 2>/dev/null | tr -dc '0-9'
}

# Alert lines carrying <sid> that Suricata marked [Drop], which it writes only
# when it actually withheld the packet. An alert line without it is a record
# that the packet matched and went on its way.
drops_for_sid() {   # <sid>
    docker exec "$SERVER_CTN" sh -c \
        "grep '\[1:$1:' '$FAST_LOG' 2>/dev/null | grep -c '\[Drop\]'" 2>/dev/null | tr -dc '0-9'
}

# The last alert line for <sid>, for a status display that shows one example
# rather than a count alone.
last_alert_for_sid() {   # <sid>
    docker exec "$SERVER_CTN" sh -c \
        "grep '\[1:$1:' '$FAST_LOG' 2>/dev/null | tail -1"
}

# True when suricata.yaml lists the local rules file. The learner's first edit
# in Part 2, and the one whose omission produces a Suricata that starts cleanly
# and matches nothing.
local_rules_configured() {
    docker exec "$SERVER_CTN" sh -c \
        "grep -qE '^[[:space:]]*-[[:space:]]*(/etc/suricata/rules/)?local.rules[[:space:]]*\$' '$SURICATA_YAML'"
}

# True when the nfq block has been uncommented. Read from `mode: accept` alone:
# it is the setting that decides what Suricata does with a queued packet, and
# the only one in the block this lab depends on.
nfq_configured() {
    docker exec "$SERVER_CTN" sh -c \
        "awk '/^nfq:/ { inb = 1; next } /^[a-z]/ { inb = 0 } inb && /^[[:space:]]+mode:[[:space:]]*accept/ { found = 1 } END { exit !found }' '$SURICATA_YAML'"
}
