#!/usr/bin/env bash
# Shared definitions for the ddos lab.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, addresses, interface names, the two shaper rates, every flood parameter
# the handout quotes, and every file path the lab writes. Every other script
# sources it; never hardcode any of these in a second place.
#
# The lab is three floods against one victim behind one bottleneck. Each flood
# exhausts a different resource -- the victim's downlink, its connection state,
# its uplink -- and each mitigation works at exactly one of those layers, so the
# flood that defeats it is the next one up.
#
# Nothing here is an answer the learner has to find. The amplification factors,
# the three-quarters backlog rule and the required query rates are arithmetic the
# learner does from measurements; no script prints them, and status.sh is written
# to withhold them.

AS=129
LAYER=L4
DC=LAB

# ---------------------------------------------------------------------------
# Three legs on one router, the botnet lab's topology with a different service
# map.
#
#   inside    the victim: one server attacked at three layers (tcp/80, tcp/5201,
#             udp/53) so one measuring instrument covers all three.
#   field     the four flood sources, the two reflectors, and the site's admin
#             workstation, which is the measurement.
#   operator  the console every stage is driven from, and the host that serves
#             the flood tool's source text.
#
# The reflectors sit on the same segment as the sources on purpose: a spoofed
# query never crosses the router, so everything the victim's network sees is
# reply traffic from two well-behaved servers.
#
# The router FORWARDS and does not translate, so every packet still carries the
# address of the machine that sent it, and a forged one still carries the forgery.
INSIDE_SUBNET="129.0.0.0/24"
FIELD_SUBNET="129.1.0.0/24"
OPERATOR_SUBNET="129.2.0.0/24"
PREFIXLEN=24

R_INSIDE_IP="129.0.0.1"
R_FIELD_IP="129.1.0.1"
R_OP_IP="129.2.0.1"

# --- inside ----------------------------------------------------------------
SERVER_IP="129.0.0.20"

# --- field -----------------------------------------------------------------
#
# host1..host4 are the flood sources; host5 and host6 are the two reflectors,
# which are honest servers and never run an attack. The admin workstation sits
# on this leg and not on the inside leg, which is a correction to the brief and
# not a preference: a qdisc shapes only what leaves the interface it is on, and
# an inside host measuring the victim never crosses the shaped interface at all.
# An inside admin pushed 8 Mbit/s through a 1 Mbit/s bottleneck with the router's
# counters not moving by a byte.
HOST1_IP="129.1.0.42"
HOST2_IP="129.1.0.13"
HOST3_IP="129.1.0.68"
HOST4_IP="129.1.0.27"
HOST5_IP="129.1.0.88"        # DNS reflector   (dnsmasq)
HOST6_IP="129.1.0.53"        # NTP reflector   (ntpsec)
ADMIN_IP="129.1.0.77"

FIELD_HOSTS=(host1 host2 host3 host4 host5 host6)
SOURCES=(host1 host2 host3 host4)
SOURCE_IPS=("$HOST1_IP" "$HOST2_IP" "$HOST3_IP" "$HOST4_IP")
DNS_REFLECTOR_IP="$HOST5_IP"
NTP_REFLECTOR_IP="$HOST6_IP"

# --- operator --------------------------------------------------------------
C2_IP="129.2.0.10"
LOADER_IP="129.2.0.40"

WEB_PORT=80
IPERF_PORT=5201
DNS_PORT=53
NTP_PORT=123
SSH_PORT=22

# The one root password the four sources share. The console logs into each
# source with it to start a flood. Credentials are not this lab's subject: the
# handout prints this password, and nothing is graded on finding it.
SOURCE_PW="Riverbed-2021"

# ---------------------------------------------------------------------------
# The bottleneck: two shapers, one per direction, both on the router.
#
# An asymmetric access link. The downlink shaper sits on the router's INSIDE
# egress, so it shapes everything arriving for the victim; the uplink shaper
# sits on the router's FIELD egress, so it shapes everything the victim sends
# out. Two shapers rather than one because response rate limiting drops
# responses: it can only restore a direction that the victim's own answers
# congest, and with only a downlink shaper Stage 3 has no mitigation at all.
#
# `ifb` is not needed for the reverse direction. Egress on the router's other
# interface is the same thing with one fewer device.
#
# `tc qdisc replace` does NOT zero the statistics; `tc qdisc del` then `add`
# does. Every "read the drop count" step, reset.sh and selftest.sh depend on
# that, and half a spike was spent reading counters that were simply cumulative.
DOWN_RATE="1mbit"            # toward the victim,  on the router's inside egress
DOWN_BURST="32kbit"
DOWN_LATENCY="50ms"
DOWN_KBIT=1000

# 256 kbit/s and not less, which is a measured floor rather than a round number.
# Stage 2's mitigation makes the victim answer every SYN with a SYN|ACK, and
# that answer stream crosses this shaper: at 400 SYNs a second against a
# 128 kbit/s uplink it fills the link on its own, the admin's own fetches are
# lost in it, and syncookies cannot restore a service it has just turned into a
# bandwidth problem. At 256 kbit/s the SYN|ACK stream of a 200 SYN/s flood is
# 98 kbit/s, and the restoration is clean: 0 of 5 fetches before, 5 of 5 after,
# with the uplink dropping nothing.
UP_RATE="256kbit"            # away from the victim, on the router's field egress
# A token bucket's burst is its bucket size, and a packet larger than the bucket
# can never acquire enough tokens to be sent: it is not slowed, it is dropped
# every time. 8kbit is 1000 bytes, which is under the 1500-byte MTU, so with
# that burst every full-size packet leaving the router toward the field is
# blackholed. The symptom is not a slow link, it is an SSH connection from the
# console that hangs forever in key exchange while ping and dig both work.
# 16kbit is 2000 bytes: above the MTU, and still a tenth of a second of this
# rate.
UP_BURST="16kbit"
UP_LATENCY="50ms"
UP_KBIT=256

# ---------------------------------------------------------------------------
# The victim's kernel knobs, all set at `docker run` because /proc/sys is
# read-only in a container without --privileged.
#
# tcp_syncookies starts at 0 because turning it on is Stage 2's mitigation and a
# defence that is already on is not a defence the learner applies.
#
# tcp_max_syn_backlog is pinned at 128 so the three-quarters plateau is a number
# that fits on a screen, and so question 8's three measurements start from a
# known one.
#
# tcp_no_metrics_save=1 is load-bearing and is not tuning. The kernel's
# pre-emptive SYN drop exempts a peer it holds TCP metrics for, and the admin's
# probe makes the admin exactly such a peer: with metrics saved, its fetches
# sail through a 1000 SYN/s flood and the attack denies nothing. `ip tcp_metrics
# flush` is not an alternative -- it returns EPERM under a rootless daemon.
# 32, and the size is what makes the denial deterministic rather than a race.
# The kernel drops an unproven peer's SYN once fewer than max_syn_backlog >> 2
# slots remain, so the queue plateaus at three-quarters of the backlog plus one
# and stays there -- but every entry eventually times out, and each timeout frees
# a slot that the next SYN to arrive takes. With a 128-deep backlog there are 97
# entries expiring and refilling, the hole that opens is wide enough for the
# admin's own fetches to slip through, and the service measures as 2 to 5 of 10
# rather than down. With 32 the hole is a quarter the size and refills in a
# tenth of a second: measured 0 of 5 fetches at eight consecutive samples across
# 150 seconds.
#
# Question 8's three points then come from the learner setting 64 and 128
# themselves, which is the same arithmetic from the other direction.
SYN_BACKLOG=32
LISTEN_BACKLOG=128           # lighttpd's server.listen-backlog; see below

# ---------------------------------------------------------------------------
# The flood parameters, one set per stage. The handout quotes these; the selftest
# runs them; neither may drift from the other.
#
# --pps and --count are mandatory on every `flood` run and have no defaults.
# Unpaced, the tool's UDP loop reaches 117578 packets a second. The count is what
# bounds a run without anybody having to kill it, and it is the whole of the
# laptop-safety argument.
S1_QNAME="amazon.com"        # the largest of the reflector's four TXT sets
S1_PPS=150
S1_COUNT=9000                # 60 s per source: long enough for the whole of the
                             # Stage 1 measurement to happen inside one run
S1_NAMES=(amplify.lab google.com spotify.com amazon.com)

# 50 a source, 200 in total. High enough that the queue is full within three
# seconds and stays full, low enough that the SYN|ACK stream syncookies produces
# (200 packets a second, 98 kbit/s) fits the uplink with room to spare.
S2_PPS=50
# 120 s per source, which is long enough for the whole of Stage 2 to happen
# inside one run: fill the queue, measure it, measure the service, measure the
# link, then turn syncookies on and measure the service again. 400 SYNs a second
# in total is 64 kbit/s, so the length costs nothing.
S2_COUNT=6000                # 120 s per source
S2_PORT="$WEB_PORT"

S3_PPS=90
S3_COUNT=8100                # 90 s per source, 360 queries a second in total
S3_ZONE="lab"

FLOOD_LOG="/tmp/flood.log"
FLOOD_BIN="/usr/local/bin/flood"
FLOOD_SRC="/var/www/localhost/htdocs/flood"
FLOOD_URL="http://${LOADER_IP}/flood"

# ---------------------------------------------------------------------------
# The victim's services and the names they serve.
ZONE_NAME="lab"
ZONE_FILE="/var/bind/lab.zone"
VALID_NAME="www.lab"         # a name that exists: the honest DNS probe
NAMED_CONF="/etc/bind/named.conf"
NAMED_LOG="/var/log/named.log"
NAMED_STATS="/var/bind/named.stats"
# Response rate limiting is written into its own file, included from options{}
# in named.conf. The baseline file holds a comment and nothing else, so turning
# RRL on is one heredoc and one `rndc reload`, and a reset is the same heredoc.
RRL_CONF="/etc/bind/rate-limit.conf"
BIG_PAGE="report.bin"        # a 100 kB object, for timing a transfer over the link
WEB_INDEX="/var/www/localhost/htdocs/index.html"

# BIND response rate limiting, Stage 3's mitigation. nxdomains-per-second is the
# only limit configured: it prices exactly the class of response the flood
# produces, and leaves every valid answer alone. No exempt-clients and no prefix
# tuning are needed, which is what question 17 is built on.
RRL_NXDOMAINS_PER_SECOND=5
RRL_PREFIX_LEN=32
RRL_WINDOW=5
RRL_SLIP=0

# ---------------------------------------------------------------------------
# The admin workstation's measurement instrument. `probe` runs the four
# measurements the oracle table is made of and writes one line each to a state
# file, so status.sh reports what the network did for the admin without opening
# a connection of its own. It takes no default target: every run names the
# victim.
PROBE_STATE="/var/lib/minilabs/probe.state"
PROBE_IPERF_RATE="900k"      # 90 % of the downlink: full when nothing else is running
PROBE_IPERF_SECS=5
PROBE_WEB_TRIES=10
PROBE_DIG_TRIES=10
PROBE_PING_COUNT=20
PROBE_PING_INTERVAL="0.2"

# The two-packet-size measurement behind question 18, and the one number in this
# lab that is NOT taken with iperf3.
#
# The claim being measured is that a token bucket's queue limit is a byte count,
# so a small packet fits in headroom a full-size one does not. Measuring it needs
# two streams of different packet size offering the SAME bandwidth, and iperf3
# cannot be trusted to report either of them here: under this much loss its
# summary travels over a control connection crossing the same congested link,
# and at `-l 100` iperf3 3.16 has been seen to die with a segmentation fault
# instead of printing a result at all. Both failures are silent -- an empty
# string parses as nothing, and the old check compared one empty string with
# another and passed.
#
# ping computes its own loss locally from the replies it got, always prints it,
# and never needs a control connection. The two settings below offer 114 and
# 113 kbit/s, which is as close to equal as round numbers get, and the smaller
# packets are the ones offering slightly MORE bandwidth, so the result cannot be
# explained by the small stream being gentler.
#
# Measured across nine samples: small 0 to 61 %, large 85 to 100 %, the gap never
# below 27 points. selftest.sh asserts the shape -- both figures present, the
# large one above 80, the gap above 20 -- and not a point value.
DGRAM_SMALL_SIZE=72          # 114 bytes on the wire, 125 a second = 114 kbit/s
DGRAM_SMALL_COUNT=250
DGRAM_SMALL_INTERVAL=0.008
DGRAM_LARGE_SIZE=1372        # 1414 bytes on the wire, 10 a second = 113 kbit/s
DGRAM_LARGE_COUNT=20
DGRAM_LARGE_INTERVAL=0.1

# Bands. Restored is above 80 % of the measured baseline, collapsed is below 20 %.
BAND_RESTORED_PCT=80
BAND_COLLAPSED_PCT=20

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<switch>
# convention, so a machine's interface says which leg it is on. The router holds
# one of each, and the two shapers hang off the first two.
IF_INSIDE="${AS}-S1"
IF_FIELD="${AS}-S2"
IF_OP="${AS}-S3"

SWITCHES=(S1 S2 S3)
SW_INSIDE_CTN="${AS}_${LAYER}_${DC}_S1"
SW_FIELD_CTN="${AS}_${LAYER}_${DC}_S2"
SW_OP_CTN="${AS}_${LAYER}_${DC}_S3"
BR="br0"
sw_port_of() { echo "${AS}-$1"; }        # 129-server, 129-host1, 129-c2, ...

# ---------------------------------------------------------------------------
# Container names: <AS>_<LAYER>_<DC>_<name>.
ROUTER_CTN="${AS}_${LAYER}_${DC}_router"
SERVER_CTN="${AS}_${LAYER}_${DC}_server"
ADMIN_CTN="${AS}_${LAYER}_${DC}_admin"
C2_CTN="${AS}_${LAYER}_${DC}_c2"
LOADER_CTN="${AS}_${LAYER}_${DC}_loader"

ctn_of() { echo "${AS}_${LAYER}_${DC}_$1"; }

# Every device that gets a starter config, in apply order: the router first so
# there is a path between the legs and both shapers are attached, then the
# victim and the loader so there is something to attack and something to read,
# then the reflectors, the sources, and the admin last so its first probe has
# somewhere to probe.
DEVICES=(router server loader c2 host5 host6 host1 host2 host3 host4 admin)

# Every machine in the lab, for teardown and for the container census.
ALL_ROLES=(router server admin host1 host2 host3 host4 host5 host6 c2 loader S1 S2 S3)

ip_of() {   # <role> -> the address on its own leg
    case "$1" in
        router) echo "$R_FIELD_IP" ;;
        server) echo "$SERVER_IP" ;;
        admin)  echo "$ADMIN_IP" ;;
        host1)  echo "$HOST1_IP" ;;
        host2)  echo "$HOST2_IP" ;;
        host3)  echo "$HOST3_IP" ;;
        host4)  echo "$HOST4_IP" ;;
        host5)  echo "$HOST5_IP" ;;
        host6)  echo "$HOST6_IP" ;;
        c2)     echo "$C2_IP" ;;
        loader) echo "$LOADER_IP" ;;
        *)      echo "" ;;
    esac
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_ddos"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed". --no-mlockall is what
# makes this lab boot on a rootless daemon.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it.
#
# An image is otherwise only rebuilt when it is missing, which means an edit to
# image/flood never reaches a machine that built the image once.
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
# needs docker access and nothing else.
HELPER_CTN="$( ctn_of netadmin_helper )"

_d="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
while [ "$_d" != "/" ] && [ ! -f "$_d/lib/helper.sh" ]; do _d="$( dirname "$_d" )"; done
[ -f "$_d/lib/helper.sh" ] || { echo "lib/helper.sh not found above ${BASH_SOURCE[0]}" >&2; return 1; }
source "$_d/lib/helper.sh"
unset _d

# ---------------------------------------------------------------------------
# Shared read-only probes. status.sh, reset.sh and selftest.sh all need these,
# and a second copy of any of them is a chance for the three to disagree about
# what the lab's state is.

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# --- the bottleneck --------------------------------------------------------
#
# `tc -s qdisc show dev X` prints two lines; the second carries the counters:
#   Sent <bytes> bytes <pkts> pkt (dropped <n>, overlimits <n> requeues <n>)

qdisc_show() {   # <interface>
    docker exec "$ROUTER_CTN" tc -s qdisc show dev "$1" 2>/dev/null
}

qdisc_field() {  # <interface> <sent_bytes|sent_pkt|dropped|overlimits>
    qdisc_show "$1" | awk -v want="$2" '
        /Sent/ {
            gsub(/[(),]/, "")
            for (i = 1; i <= NF; i++) {
                if ($i == "Sent")       sent_bytes = $(i+1)
                if ($i == "pkt")        sent_pkt   = $(i-1)
                if ($i == "dropped")    dropped    = $(i+1)
                if ($i == "overlimits") overlimits = $(i+1)
            }
            if (want == "sent_bytes") print sent_bytes + 0
            if (want == "sent_pkt")   print sent_pkt + 0
            if (want == "dropped")    print dropped + 0
            if (want == "overlimits") print overlimits + 0
            exit
        }'
}

# Dropped as a percentage of everything the qdisc was offered (sent + dropped),
# to one decimal place. 0.0 when nothing has been offered at all.
qdisc_drop_pct() {   # <interface>
    local sent dropped
    sent="$( qdisc_field "$1" sent_pkt )"
    dropped="$( qdisc_field "$1" dropped )"
    awk -v s="${sent:-0}" -v d="${dropped:-0}" \
        'BEGIN { t = s + d; if (t <= 0) { print "0.0" } else { printf "%.1f", 100 * d / t } }'
}

# Remove and re-add a shaper, which is the only way to zero its statistics:
# `tc qdisc replace` keeps them. Every step that reads a drop count starts here.
qdisc_reset() {   # <interface>
    local dev="$1" rate burst latency
    if [ "$dev" = "$IF_INSIDE" ]; then rate="$DOWN_RATE"; burst="$DOWN_BURST"; latency="$DOWN_LATENCY"
    else                               rate="$UP_RATE";   burst="$UP_BURST";   latency="$UP_LATENCY"; fi
    docker exec "$ROUTER_CTN" sh -c \
        "tc qdisc del dev $dev root 2>/dev/null; tc qdisc add dev $dev root tbf rate $rate burst $burst latency $latency"
}

qdisc_rate_of() {   # <interface> -> the rate tc reports, e.g. 1Mbit
    qdisc_show "$1" | awk '/qdisc tbf/ { for (i=1;i<=NF;i++) if ($i == "rate") { print $(i+1); exit } }'
}

# --- the victim's side -----------------------------------------------------

# Half-open connections. `ss -H` drops the header line, which is the difference
# between a count of 0 and a count of 1 on an idle server.
synrecv() {
    docker exec "$SERVER_CTN" sh -c "ss -Htan state syn-recv | wc -l" 2>/dev/null | tr -dc '0-9'
}

server_sysctl() {   # <key>
    docker exec "$SERVER_CTN" sh -c "cat /proc/sys/net/ipv4/$1 2>/dev/null" 2>/dev/null | tr -dc '0-9'
}

# A per-namespace SNMP counter on the victim, read absolutely (-a) so reading it
# does not reset it and a second reading is comparable with the first.
server_nstat() {   # <counter name>
    docker exec "$SERVER_CTN" sh -c "nstat -az 2>/dev/null | grep -w '$1'" 2>/dev/null \
        | awk '{ print $2 + 0 }'
}

router_nstat() {   # <counter name>
    docker exec "$ROUTER_CTN" sh -c "nstat -az 2>/dev/null | grep -w '$1'" 2>/dev/null \
        | awk '{ print $2 + 0 }'
}

# The strict-uRPF drop counter, per network namespace. Read with nstat and not
# from dmesg: dmesg fails under a rootless daemon, because the host sets
# kernel.dmesg_restrict=1 and a rootless container's CAP_SYSLOG is confined to
# its own user namespace. The martian log is a second, rootful-only reading.
urpf_drops() { router_nstat TcpExtIPReversePathFilter; }

# BIND's response-rate-limiting drop count, from the statistics dump.
#
# `rndc stats` APPENDS a dump to /var/bind/named.stats on every call, so the
# first occurrence of the line is the oldest reading in the file and reading it
# reports a number from minutes ago. Take the last.
rrl_drops() {
    docker exec "$SERVER_CTN" sh -c \
        "rndc stats >/dev/null 2>&1; awk '/responses dropped for rate limits/ { v = \$1 } END { print v + 0 }' '$NAMED_STATS' 2>/dev/null" \
        2>/dev/null | tr -dc '0-9'
}

rrl_configured() {
    docker exec "$SERVER_CTN" sh -c "grep -q 'nxdomains-per-second' '$RRL_CONF'" >/dev/null 2>&1
}

# --- the router's side -----------------------------------------------------

# The FORWARD chain as the learner wrote it, with its packet and byte counters.
router_rules() {
    docker exec "$ROUTER_CTN" iptables -L FORWARD -n -v --line-numbers 2>/dev/null \
        | awk 'NR > 2 && NF'
}

router_rule_count() {
    docker exec "$ROUTER_CTN" iptables -S FORWARD 2>/dev/null | grep -vc '^-P FORWARD' || true
}

# Packets and bytes a DROP rule for one source address has absorbed.
router_rule_pkts() {   # <source address>
    docker exec "$ROUTER_CTN" iptables -L FORWARD -n -v -x 2>/dev/null \
        | awk -v s="$1" '$8 == s { print $1 + 0; exit }'
}

router_rule_bytes() {  # <source address>
    docker exec "$ROUTER_CTN" iptables -L FORWARD -n -v -x 2>/dev/null \
        | awk -v s="$1" '$8 == s { print $2 + 0; exit }'
}

# Per-interface rp_filter on the router, as the kernel has it now. The effective
# value is max(all, <interface>), and `all` is pinned to 0 at `docker run` so
# that turning the check on is something the learner does and not something the
# host's own sysctl did for them.
router_rp_filter() {   # <interface>
    docker exec "$ROUTER_CTN" sh -c "cat /proc/sys/net/ipv4/conf/$1/rp_filter 2>/dev/null" \
        2>/dev/null | tr -dc '0-9'
}

# --- the sources -----------------------------------------------------------

# Which of the four sources currently has a bounded flood running. A run exits
# on its own, so this is a statement about right now and not about what was
# started.
# The bracket around the first character is not decoration. `pgrep -f` matches
# against every process's full command line INCLUDING the `sh -c` this runs in,
# whose text contains the pattern, so a plain pattern matches itself and this
# function returns true forever. `[/]usr/local/bin/flood` is a regex that matches
# the tool's own command line and not the text of this command.
flood_running() {   # <role>
    docker exec "$( ctn_of "$1" )" sh -c "pgrep -f '[/]${FLOOD_BIN#/}' >/dev/null 2>&1" >/dev/null 2>&1
}

flooding_sources() {
    local h out=""
    for h in "${SOURCES[@]}"; do
        flood_running "$h" && out="${out:+$out }$h"
    done
    printf '%s' "$out"
}

# True when the source drops its own outbound RSTs toward the victim. Without
# that rule the victim's SYN|ACK reaches a source kernel that has no matching
# socket, the RST frees the half-open entry immediately, and the victim's
# syn-recv count never leaves zero.
source_drops_rst() {   # <role>
    docker exec "$( ctn_of "$1" )" sh -c \
        "iptables -S OUTPUT 2>/dev/null | grep -q 'tcp-flags RST RST'" >/dev/null 2>&1
}

# --- the admin's measurements ----------------------------------------------
#
# `probe` writes one line per measurement into a state file. Reading the file
# rather than running a fresh probe is deliberate: it says what the network did
# for the admin while the learner was typing, not what it does now.

# One ping run from the admin, reported as the loss percentage it printed. Prints
# nothing when ping itself could not run, which the caller checks for rather than
# turning into a zero.
ping_loss_pct() {   # <payload size> <count> <interval>
    docker exec "$ADMIN_CTN" sh -c \
        "ping -c $2 -i $3 -s $1 -W 1 $SERVER_IP 2>/dev/null | grep -o '[0-9.]*% packet loss'" \
        2>/dev/null | head -1 | sed 's/% packet loss//'
}

# The listen backlog the kernel actually gave the victim's web service, read from
# the listening socket rather than from the config file: what a handout states as
# an environment fact is what the kernel has, not what lighttpd.conf asks for.
# `ss -Hltn` prints Recv-Q then Send-Q, and for a listening socket Send-Q is the
# backlog.
listen_backlog() {
    docker exec "$SERVER_CTN" sh -c \
        "ss -Hltn 'sport = :$WEB_PORT' | awk 'NR == 1 { print \$3 }'" 2>/dev/null | tr -dc '0-9'
}

# The last result the iperf3 SERVER recorded, for the runs where the client got
# no summary back over a congested control connection. Empty when the server
# holds no complete result either, which is what happens when the client dies
# mid-test.
server_iperf_last() {   # <kbit|loss>
    local line
    line="$( docker exec "$SERVER_CTN" sh -c \
        "grep receiver /var/log/iperf3.log 2>/dev/null | tail -1" 2>/dev/null )"
    [ -n "$line" ] || return 1
    case "$1" in
        kbit) printf '%s' "$line" | awk '{ for (i=1;i<=NF;i++) if ($i == "Kbits/sec") print $(i-1) }' ;;
        loss) printf '%s' "$line" | grep -o '([0-9.]*%)' | tr -d '()%' ;;
    esac
}

probe_state() {
    docker exec "$ADMIN_CTN" sh -c "cat '$PROBE_STATE' 2>/dev/null" 2>/dev/null
}

# One field of one measurement:
#   iperf <epoch> <kbit> <loss_pct>
#   web   <epoch> <ok> <tries>
#   dig   <epoch> <ok> <tries>
#   ping  <epoch> <rtt_ms> <loss_pct>
probe_field() {   # <iperf|web|dig|ping> <field number, 3 upward>
    probe_state | awk -v k="$1" -v n="$2" '$1 == k { print $n }' | tail -1
}

# Run one measurement on the admin and return its line. The handout has the
# learner run these by hand; the scripts run the same program so the numbers in
# status.sh, the selftest and the handout cannot come from different tools.
probe_run() {   # <all|iperf|web|dig|ping>
    docker exec "$ADMIN_CTN" probe --target "$SERVER_IP" --name "$VALID_NAME" "$1" 2>&1
}

# --- waiters ---------------------------------------------------------------
#
# Nothing in this lab is instantaneous, and two things take a long time for
# reasons that are not obvious. A flood exits when its count is spent, and a
# victim's half-open entries take up to 63 seconds to drain after it does,
# because the kernel retransmits each SYN|ACK several times before giving up on
# it. Waiting on the condition rather than sleeping a fixed time is what keeps a
# Stage 2 measurement from starting on the tail of the previous one.

wait_for_cmd() {   # <timeout seconds> <command...>
    local deadline=$(( $( date +%s ) + $1 )); shift
    while [ "$( date +%s )" -lt "$deadline" ]; do
        "$@" >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# Wait until no source has a flood running.
wait_for_floods_done() {   # <timeout seconds>
    local deadline=$(( $( date +%s ) + $1 ))
    while [ "$( date +%s )" -lt "$deadline" ]; do
        [ -z "$( flooding_sources )" ] && return 0
        sleep 2
    done
    return 1
}

# Wait until the victim's half-open queue has drained to zero.
wait_for_synrecv_zero() {   # <timeout seconds>
    local deadline=$(( $( date +%s ) + $1 )) n
    while [ "$( date +%s )" -lt "$deadline" ]; do
        n="$( synrecv )"
        [ "${n:-1}" -eq 0 ] 2>/dev/null && return 0
        sleep 2
    done
    return 1
}

# Start one bounded flood on every source, from the console, over SSH, exactly
# the way the handout has the learner start it. Returns as soon as the four are
# launched; each run exits on its own when its count is spent.
start_flood_on_sources() {   # <flood argument string>
    local ip
    for ip in "${SOURCE_IPS[@]}"; do
        docker exec "$C2_CTN" sshpass -p "$SOURCE_PW" ssh -n "root@$ip" \
            "nohup flood $1 >$FLOOD_LOG 2>&1 &" >/dev/null 2>&1 || true
    done
}

# Stop anything still running, for reset.sh and for a selftest stage that has
# measured what it needed before the count ran out.
# Same bracket, and here it is the difference between stopping the floods and
# killing the shell that is doing the stopping before it reaches the last source.
stop_floods() {
    local h
    for h in "${SOURCES[@]}"; do
        docker exec "$( ctn_of "$h" )" sh -c "pkill -f '[/]${FLOOD_BIN#/}' 2>/dev/null" >/dev/null 2>&1 || true
    done
}
