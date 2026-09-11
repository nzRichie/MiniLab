#!/usr/bin/env bash
# Shared definitions for the service availability and failover lab lifecycle
# scripts. Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, interface names, service ports and file paths. Every other script
# sources it; never hardcode any of these in a second place.
#
# The lab is a configuration exercise, not an attack. Two web servers hold the
# same content and a reverse proxy sits in front of them. The learner writes the
# pool, the health check, the retry policy and the timeouts, and then breaks one
# backend three different ways. Each way fails at a different layer and a
# different mechanism is what keeps the client's request count of non-2xx
# responses at zero, which is the fact every stage is measured against.

AS=117
DC=LAB

# ---------------------------------------------------------------------------
# Two segments meeting at the proxy.
#
#   front : the client, and the only address it ever connects to. Point to
#           point, so nothing but the proxy is on it.
#   back  : the two backends and the proxy's second NIC, over a switch. The
#           backends share a broadcast domain because that is how a real pool
#           sits, and because the switch is what lets a third backend be added
#           without re-wiring anything.
#
# The proxy does NOT forward between them: net.ipv4.ip_forward is 0. That is
# what makes "behind a proxy" true rather than decorative. The client has no
# path to a backend except a TCP connection HAProxy opens on its behalf, so
# every observation the learner makes about a backend's health has to come from
# HAProxy's own statistics rather than from probing the backend directly.
#
# Both segments live inside the AS's 117.0.0.0/8 block, so subnet_config's
# AS-octet scheme holds and every address is known before a container exists.
FRONT_SUBNET="117.0.0.0/24"    # client + proxy's front NIC
BACK_SUBNET="117.1.0.0/24"     # proxy's back NIC + web1 + web2, over a switch
PREFIXLEN=24

PROXY_FRONT_IP="117.0.0.1"     # the address the client connects to; the service
PROXY_BACK_IP="117.1.0.1"      # the address HAProxy opens backend connections from
CLIENT_IP="117.0.0.10"
WEB1_IP="117.1.0.20"
WEB2_IP="117.1.0.30"

# The service, as the client knows it. One address, one port, and nothing in it
# names a backend: that indirection is the whole of what a reverse proxy buys.
VIP_URL="http://${PROXY_FRONT_IP}/"
VIP_PORT=80

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<segment>
# convention; the proxy names each of its two NICs after the segment it faces.
# web1 and web2 share a segment, so they share an interface name; what
# distinguishes them at the switch is the port name, below.
CLIENT_IF="${AS}-front"
WEB_IF="${AS}-back"            # both backends
P_FRONT_IF="front"             # proxy, facing the client
P_BACK_IF="back"               # proxy, facing the switch

SW="S1"
SW_CTN="${AS}_L7_${DC}_${SW}"
sw_port_of() { echo "${AS}-$1"; }        # 117-proxy, 117-web1, 117-web2
SWITCH_DEVICES=(proxy web1 web2)

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L7 marking the lab's
# layer: <AS>_L7_<DC>_<name>. One prefix covers every container so status and
# teardown select the lab with a single filter.
CLIENT_CTN="${AS}_L7_${DC}_client"
PROXY_CTN="${AS}_L7_${DC}_proxy"
WEB1_CTN="${AS}_L7_${DC}_web1"
WEB2_CTN="${AS}_L7_${DC}_web2"

# Every device that gets a starter config, in apply order: the backends first so
# there is something to balance over before the proxy is configured to look for
# them, then the proxy, then the client that measures both.
DEVICES=(web1 web2 proxy client)
BACKENDS=(web1 web2)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_failover"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed". --no-mlockall is what
# makes this lab boot on a rootless daemon.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# HAProxy, on the proxy.
#
# The learner edits HAPROXY_CFG and starts, checks and reloads the daemon by
# hand; nothing in this lab starts it for them after Part 1, because knowing
# that a reload takes a config file that was never validated is half of what
# "availability" means operationally.
#
# The pid file is how a reload finds the running process. `pkill -x haproxy` is
# wrong here for the same reason it is wrong for sshd: HAProxy's worker rewrites
# its argv, and each container's PID 1 is `sleep infinity`, so a signal aimed by
# name lands on the wrong process or on nothing.
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
HAPROXY_PID="/run/haproxy.pid"

# The runtime API socket. It is in the STARTER config rather than left to the
# learner because status.sh reads the pool through it: an oracle that only works
# once the learner has written the line it needs cannot report on Part 1. What
# the learner does with it is Part 5, where `set server` takes a backend out
# with sessions still in flight.
HAPROXY_SOCK="/run/haproxy/admin.sock"

# The proxy section names. Fixed here rather than left to the learner so the
# oracle can find them; what goes inside them is entirely the learner's work.
FE_NAME="fe_web"
BE_NAME="be_web"

# ---------------------------------------------------------------------------
# The backends. Both serve the same site, and each serves its own name as the
# whole body of the index page, which is what makes "which backend answered this
# request" a one-word answer the client can tally.
WEB_PORT=80                    # what lighttpd listens on inside each backend
WEB_ROOT="/var/www/localhost/htdocs"
LIGHTTPD_PID="/run/lighttpd.pid"

# The health endpoint the check in Part 2 requests. It is a separate file from
# the index page on purpose: removing it makes the check fail while the site
# itself keeps serving perfectly, which is the distinction Part 2 is about.
HEALTH_PATH="/health"
HEALTH_FILE="${WEB_ROOT}/health"
HEALTH_BODY="OK"

# ---------------------------------------------------------------------------
# The nftables table Part 4's blackhole is written in, on a backend. Named here
# so reset.sh can remove it; a learner who leaves one behind would otherwise
# start the next run with a backend already dark.
NFT_TABLE="blackhole"

# ---------------------------------------------------------------------------
# The measurement. Every claim this lab makes about availability is a count over
# a fixed request loop, so the loop's shape is defined once.
#
# LOOP_N requests at LOOP_GAP seconds apart is LOOP_N*LOOP_GAP seconds of
# traffic. The gap is not cosmetic: 40 unpaced requests over a veth pair finish
# in under a second, which is faster than a learner can switch terminals, so the
# backend would always be killed after the loop had already ended and every run
# would report a clean sweep. The gap is what makes "mid-run" mean anything.
LOOP_N=40
LOOP_GAP=0.2
LOOP_KILL_AT=3            # seconds into the loop that selftest breaks a backend
CURL_MAX_TIME=5           # the client's own patience; timeout connect must fit inside it

# The health check the answer key writes, and the numbers the handout has the
# learner compute a detection window from.
CHECK_INTER="1s"
CHECK_FALL=2
CHECK_RISE=3

# The retry policy the answer key writes.
RETRIES=3

# The two connect timeouts Part 4 compares. The first is the answer key's
# starting value and the second is what the learner tunes it to.
CONNECT_TIMEOUT_SLOW="5s"
CONNECT_TIMEOUT_FAST="200ms"

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

# Image preflight, called by spawn.sh before the first `docker run`. The switch
# image is pulled rather than built; the host image is this lab's own.
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

# Run one privileged networking command inside the helper.
helper() { docker exec "$HELPER_CTN" "$@"; }

helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }

# ---------------------------------------------------------------------------
# Shared read-only probes. status.sh and selftest.sh both need these, and a
# second copy of any of them is a chance for the two to disagree about what the
# lab's success condition is.

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# --- HAProxy's own state ---------------------------------------------------

# Whether the configuration file currently on the proxy would start. `haproxy -c`
# parses and exits without binding anything, which is the check the learner runs
# before every reload: a reload with an invalid file leaves the OLD process
# serving and prints the reason, and a start with one leaves nothing serving.
hap_config_valid()   { docker exec "$PROXY_CTN" haproxy -c -f "$HAPROXY_CFG" >/dev/null 2>&1; }
hap_config_message() { docker exec "$PROXY_CTN" haproxy -c -f "$HAPROXY_CFG" 2>&1 | tail -4 | tr -d '\r'; }

# Whether a daemon is actually serving. The pid file alone is not enough: a
# process that failed to bind leaves the file behind, so the pid in it is
# signalled with 0 to ask the kernel whether anything still holds it.
hap_running() {
    docker exec "$PROXY_CTN" sh -c \
        "[ -f $HAPROXY_PID ] && kill -0 \"\$(cat $HAPROXY_PID)\" 2>/dev/null" >/dev/null 2>&1
}

hap_start()  { docker exec "$PROXY_CTN" haproxy -D -f "$HAPROXY_CFG" -p "$HAPROXY_PID"; }

# A reload, not a restart. -sf tells the new process to signal the old one to
# finish the requests it already accepted and then exit, so the listening socket
# is never unowned and a client mid-request is never cut off.
hap_reload() {
    docker exec "$PROXY_CTN" sh -c \
        "haproxy -D -f $HAPROXY_CFG -p $HAPROXY_PID -sf \"\$(cat $HAPROXY_PID)\""
}

hap_stop() {
    docker exec "$PROXY_CTN" sh -c \
        "[ -f $HAPROXY_PID ] && kill \"\$(cat $HAPROXY_PID)\" 2>/dev/null; rm -f $HAPROXY_PID; exit 0"
}

# One command over the runtime API socket, and its reply.
hap_socket() {   # <command>
    docker exec "$PROXY_CTN" sh -c "echo '$1' | socat ${HAPROXY_SOCK} stdio" 2>/dev/null | tr -d '\r'
}

hap_stat() { hap_socket "show stat"; }

# Read one field of one server's row out of `show stat`, BY COLUMN NAME.
#
# The first CSV line is a header beginning "# pxname,svname,...", so the column
# index is derived from the data rather than hardcoded. HAProxy has added columns
# between releases and a hardcoded index silently reads a neighbouring column,
# which is the kind of error that makes an oracle report a lie rather than fail.
server_field() {   # <server name> <column name>
    hap_stat | awk -F, -v want="$1" -v col="$2" -v be="$BE_NAME" '
        NR == 1 { sub(/^# /, "", $0); n = split($0, h, ","); for (i = 1; i <= n; i++) if (h[i] == col) idx = i; next }
        idx && $1 == be && $2 == want { print $idx; exit }
    '
}

# UP, DOWN, DRAIN, MAINT, or "-" when HAProxy is not serving this server at all.
server_status() { local v; v="$( server_field "$1" status )"; echo "${v:--}"; }

# What the last health check produced. L7OK is a check that got the status code
# it expected; L7STS is one that got a DIFFERENT status code, so the service
# replied and the check still failed; L4CON is a refused connection; L4TOUT is a
# connection that got no answer at all. Those four are how a learner tells apart
# the three ways this lab breaks a backend.
# A check that is running right now is reported with a leading "* ", so a reading
# taken while one is in flight would not compare equal to the same result taken a
# moment later. The marker is stripped; what is left is the result of the last
# COMPLETED check, which is what every claim in this lab is about.
server_check() {
    local v; v="$( server_field "$1" check_status )"
    v="${v#\* }"
    echo "${v:--}"
}

# Sessions this server has handled since HAProxy started. The difference between
# two readings is how the drain in Part 5 is observed: a drained server's count
# stops growing while the pool keeps serving.
server_stot()   { local v; v="$( server_field "$1" stot )"; echo "${v:-0}"; }

# How many servers in the pool HAProxy currently considers usable.
active_servers() {
    local n=0 w
    for w in "${BACKENDS[@]}"; do
        [ "$( server_status "$w" )" = UP ] && n=$(( n + 1 ))
    done
    echo "$n"
}

# One directive as it currently stands in the config file, or "" when the learner
# has not written it yet. `|| true` is load-bearing: grep exits 1 on no match, and
# under `set -o pipefail` in the caller that would abort the whole status run at
# the first directive the learner has not reached.
cfg_directive() {   # <extended regex>
    docker exec "$PROXY_CTN" sh -c \
        "grep -hE '$1' $HAPROXY_CFG 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' || true" 2>/dev/null
}

# --- what the client actually sees -----------------------------------------

# Run <n> requests from the client at <gap> seconds apart, printing one line per
# request:  <http status> <seconds> <backend that served it>
#
# The backend is read off the body, because each backend serves its own name as
# the whole of its index page. A body that is not one of those names, which is
# what HAProxy's own error pages are, prints as "-": the request was answered by
# the proxy itself and no backend saw it.
#
# curl's -w output is written even when the transfer failed, and %{http_code} is
# then 000, so a connection that never completed is a line in the log rather than
# a gap in it.
client_loop() {   # [n] [gap]
    local n="${1:-$LOOP_N}" gap="${2:-$LOOP_GAP}"
    docker exec "$CLIENT_CTN" sh -c '
        n=$1; gap=$2; url=$3; maxt=$4; i=0
        while [ "$i" -lt "$n" ]; do
            i=$(( i + 1 ))
            : > /tmp/body
            ct="$( curl -s -m "$maxt" -o /tmp/body -w "%{http_code} %{time_total}" "$url" 2>/dev/null )"
            [ -n "$ct" ] || ct="000 $maxt"
            m="$( head -1 /tmp/body 2>/dev/null | tr -d "\r" )"
            case "$m" in web1|web2) ;; *) m="-" ;; esac
            echo "$ct $m"
            sleep "$gap"
        done
    ' sh "$n" "$gap" "$VIP_URL" "$CURL_MAX_TIME"
}

# Tallies over a file of client_loop lines. The first is the lab's headline
# oracle: the number of requests the client did not get a 2xx for.
loop_nonok()   { awk '$1 !~ /^2/ { c++ } END { print c + 0 }' "$1"; }
loop_total()   { awk 'END { print NR + 0 }' "$1"; }
loop_served()  { awk -v m="$2" '$3 == m { c++ } END { print c + 0 }' "$1"; }
loop_maxtime() { awk '{ if ($2 + 0 > m) m = $2 + 0 } END { printf "%.3f\n", m + 0 }' "$1"; }
loop_codes()   { awk '{ print $1 }' "$1" | sort | uniq -c | awk '{ printf "%s x%s  ", $2, $1 }'; echo; }

# The status code the client was given for the requests that did not succeed.
# "000" is curl's own marker for a transfer that never produced a status line,
# which is what a request that ran out of time before any reply arrived looks
# like; anything else came from HAProxy or from a backend.
loop_fail_code() { awk '$1 !~ /^2/ { print $1; exit }' "$1"; }
loop_split()   { awk '{ print $3 }' "$1" | sort | uniq -c | awk '{ printf "%s x%s  ", $2, $1 }'; echo; }

# --- reaching things directly ----------------------------------------------

# What nmap reports for one TCP port from one container. -Pn is not optional: the
# proxy does not forward, so its own host discovery probes go unanswered and
# every scan of a backend from the client would report nothing at all rather than
# reporting that the port cannot be reached.
port_state() {   # <from container> <address> <port>
    docker exec "$1" nmap -Pn -n --host-timeout 20s -p "$3" "$2" 2>/dev/null \
        | awk -v p="$3/tcp" '$1 == p { print $2; exit }'
}

# Fetch a backend's index page FROM THE PROXY, which is the only machine with a
# route to the back segment. This is how the learner confirms that a backend
# HAProxy has marked DOWN is still serving its site perfectly: the check failed,
# the service did not.
backend_body() {   # <web1|web2>
    local ip; ip="$( backend_ip "$1" )"
    docker exec "$PROXY_CTN" curl -s --max-time 5 "http://${ip}/" 2>/dev/null | head -1 | tr -d '\r'
}

backend_health_code() {   # <web1|web2>  -> the status code its /health returns
    local ip; ip="$( backend_ip "$1" )"
    docker exec "$PROXY_CTN" curl -s -o /dev/null --max-time 5 \
        -w '%{http_code}' "http://${ip}${HEALTH_PATH}" 2>/dev/null
}

backend_ip() {   # <web1|web2>
    case "$1" in
        web1) echo "$WEB1_IP" ;;
        web2) echo "$WEB2_IP" ;;
        *)    echo "" ;;
    esac
}

# --- the three ways this lab breaks a backend ------------------------------
# Each one fails at a different layer, and the whole lab is the observation that
# a different mechanism keeps the client's failure count at zero for each.

# Part 2: the site keeps serving and only the health endpoint stops answering
# with 200. Nothing has crashed; the check is what removes the server.
break_health() { docker exec "$( ctn_of "$1" )" mv "$HEALTH_FILE" "${HEALTH_FILE}.off"; }
fix_health()   { docker exec "$( ctn_of "$1" )" mv "${HEALTH_FILE}.off" "$HEALTH_FILE"; }

# Part 3: the process is gone, so the kernel answers a connection attempt with a
# TCP reset immediately. A retry costs nothing and a redispatch saves the request.
kill_backend() {
    docker exec "$( ctn_of "$1" )" sh -c "kill -9 \"\$(cat $LIGHTTPD_PID)\" 2>/dev/null; exit 0"
}

# Bring a killed backend back by re-running its starter config, which is
# idempotent, rather than by starting lighttpd here. One definition of how a
# backend is supposed to be set up, in default_config/, and reset.sh reuses it.
revive_backend() {   # <web1|web2>
    local ctn; ctn="$( ctn_of "$1" )"
    docker exec "$ctn" "/home/$1.sh" >/dev/null 2>&1
}

# Part 4: the packets are dropped rather than refused, so a connection attempt
# gets no answer at all and only a timeout ends it. This is what a crashed
# machine, a full state table or a filter in the path looks like from a proxy,
# and it is the case the retry policy alone does not make free.
blackhole_on() {   # <web1|web2>
    docker exec "$( ctn_of "$1" )" sh -c "
        nft add table inet $NFT_TABLE 2>/dev/null
        nft 'add chain inet $NFT_TABLE input { type filter hook input priority filter ; policy accept ; }' 2>/dev/null
        nft add rule inet $NFT_TABLE input tcp dport $WEB_PORT drop"
}

blackhole_off() {   # <web1|web2>
    docker exec "$( ctn_of "$1" )" sh -c "nft delete table inet $NFT_TABLE 2>/dev/null; exit 0"
}

blackhole_present() {   # <web1|web2>
    docker exec "$( ctn_of "$1" )" sh -c "nft list table inet $NFT_TABLE 2>/dev/null | grep -q drop"
}

# Part 5: taking a server out on purpose, with nothing broken. drain stops new
# sessions being assigned to it and lets the ones in flight finish; maint stops
# its health checks as well, so a server under maintenance does not come back on
# its own when whatever was wrong with it starts answering again.
set_server_state() {   # <web1|web2> <ready|drain|maint>
    hap_socket "set server ${BE_NAME}/$1 state $2"
}
