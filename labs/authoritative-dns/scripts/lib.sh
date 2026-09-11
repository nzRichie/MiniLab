#!/usr/bin/env bash
# Shared definitions for the authoritative DNS lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnet, container
# names, addresses, zone names, file paths and the record set the learner is
# building towards. Every other script sources it; never hardcode any of these in
# a second place.
#
# The lab is a configuration exercise, not an attack. Three name servers arrive
# running named with no zone of any kind, and the learner writes every zone file
# and every zone statement on them: a forward zone on the primary, a copy of it
# on the secondary, a child zone on the third server, and the reverse zone for
# this lab's /24 back on the primary.
#
# Two things are given and are never the learner's work. The root server holds
# the three zones above uni.lab, so the delegation chain the learner extends is
# a real one a resolver walks down rather than a static pointer. The client runs
# a recursive resolver with nothing but a hints file naming that root server, so
# every end-to-end check in the lab is answered by iteration from the root.

AS=115
DC=LAB

# ---------------------------------------------------------------------------
# One switched segment. Nothing in this lab crosses a subnet boundary, so there
# is no router: every machine can reach every other machine from the moment
# spawn.sh finishes, and everything that fails afterwards fails in the DNS.
SUBNET="115.0.0.0/24"
PREFIXLEN=24

# IPv6 alongside it, so the AAAA record the learner writes in Part 1 names an
# address that really answers rather than a string nothing checks. fd00::/8 is
# the unique-local range, which is to IPv6 what RFC 1918 is to IPv4: it is not
# routed on the public internet, which is what makes it safe on an isolated
# bridge.
SUBNET6="fd00:115::/64"
PREFIXLEN6=64

ROOT_IP="115.0.0.2"          # the root server: given, and never edited by the learner
PRIMARY_IP="115.0.0.10"      # ns1.uni.lab, primary for the forward zone and the reverse /24
SECONDARY_IP="115.0.0.20"    # ns2.uni.lab, secondary for the forward zone; also mail.uni.lab
SUB_IP="115.0.0.30"          # ns1.cs.uni.lab, the delegated child zone's only server
CLIENT_IP="115.0.0.40"       # the recursive resolver, and the vantage every dig is run from

ROOT_IP6="fd00:115::2"
PRIMARY_IP6="fd00:115::10"
SECONDARY_IP6="fd00:115::20"
SUB_IP6="fd00:115::30"
CLIENT_IP6="fd00:115::40"

# ---------------------------------------------------------------------------
# Interface names. Every machine has one NIC, on the one segment, so they all
# carry the platform's <AS>-<segment> name; what distinguishes them at the
# switch is the port name below.
HOST_IF="${AS}-S1"

SW="S1"
SW_CTN="${AS}_L7_${DC}_${SW}"
sw_port_of() { echo "${AS}-$1"; }        # 115-root, 115-primary, ...

# ---------------------------------------------------------------------------
# The names. uni.lab is the same zone the DNS cache-poisoning lab attacks; this
# lab builds the authoritative side of it.
ZONE="uni.lab"                       # the forward zone the learner authors on the primary
CHILD_ZONE="cs.uni.lab"              # the child zone, delegated away from it in Part 3
REVERSE_ZONE="0.0.115.in-addr.arpa"  # the reverse zone for this lab's /24

# The names inside the zone the oracle asks for, and the value each one must
# resolve to when the zone is finished. status.sh prints this table and
# selftest.sh asserts it, so a change here is a change to the lab's definition of
# done and to nothing else.
NS1_NAME="ns1.${ZONE}"               # A  -> PRIMARY_IP
NS2_NAME="ns2.${ZONE}"               # A  -> SECONDARY_IP
MAIL_NAME="mail.${ZONE}"             # A  -> SECONDARY_IP, and the target of the MX
WWW_NAME="www.${ZONE}"               # A  -> PRIMARY_IP, AAAA -> PRIMARY_IP6
WEB_NAME="web.${ZONE}"               # CNAME -> WWW_NAME
CLIENT_NAME="client.${ZONE}"         # A  -> CLIENT_IP
CHILD_NS_NAME="ns1.${CHILD_ZONE}"    # A  -> SUB_IP, and the glue record in the parent
CHILD_WWW_NAME="www.${CHILD_ZONE}"   # A  -> SUB_IP
MX_PREFERENCE=10

# The name the negative-answer questions are asked about. Nothing in either zone
# may ever define it: the SOA that comes back in the authority section, and the
# TTL on that SOA, are what Part 1 reads off it.
ABSENT_NAME="nothere.${ZONE}"

# ---------------------------------------------------------------------------
# The zones above uni.lab, all three served by the root container and all three
# given. They exist so the client resolves by walking down a real delegation
# chain: root -> lab -> uni.lab -> cs.uni.lab. `dig +trace` from the client
# prints that walk, which is what makes the referral the learner creates in
# Part 3 something they can watch a resolver follow.
ROOT_NS_NAME="ns.root-lab."          # the root server's own name
TLD_ZONE="lab"                       # delegates uni.lab to ns1 and ns2, with glue
ARPA_ZONE="arpa"                     # delegates the reverse /24 to ns1, without glue

# ---------------------------------------------------------------------------
# Where named keeps things. The same layout on every server, so a command in the
# handout reads the same whichever machine it is typed on.
BIND_DIR="/var/bind"                 # zone files live here; named's working directory
NAMED_CONF="/etc/bind/named.conf"    # given, and holds only an options block plus the include
ZONES_CONF="/etc/bind/zones.conf"    # included by named.conf, and empty at spawn: the learner's
NAMED_LOG="/var/log/named.log"       # named's own log, which is half the lab's oracle

zone_file_of() { echo "${BIND_DIR}/$1.zone"; }   # /var/bind/uni.lab.zone, and so on

# ---------------------------------------------------------------------------
# The HTTP identity each web name serves. It is the one check in the lab that
# does not read a DNS answer: a name resolved through the whole chain, connected
# to, and the machine at the other end saying which one it is.
PARENT_WEB_MARKER="UNI-MAIN-4B71E2"    # served by the primary,  answers www.uni.lab
CHILD_WEB_MARKER="CS-DEPT-9F03A6"      # served by the sub,      answers www.cs.uni.lab

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L7 marking the lab's
# layer: <AS>_L7_<DC>_<name>. One prefix covers every container so status and
# teardown select the lab with a single filter.
ROOT_CTN="${AS}_L7_${DC}_root"
PRIMARY_CTN="${AS}_L7_${DC}_primary"
SECONDARY_CTN="${AS}_L7_${DC}_secondary"
SUB_CTN="${AS}_L7_${DC}_sub"
CLIENT_CTN="${AS}_L7_${DC}_client"

# Every device that gets a starter config, in apply order: the root first, so the
# chain above uni.lab is answering before anything below it is asked for, then
# the three servers the learner works on, then the client that measures them.
DEVICES=(root primary secondary sub client)

# The three machines the learner configures. reset.sh empties exactly these and
# nothing else.
LEARNER_DEVICES=(primary secondary sub)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_zonedns"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed". --no-mlockall is what
# makes this lab boot on a rootless daemon.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

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
#
# Every probe here runs dig inside a lab container rather than on the host, so
# nothing depends on the host having dig, and every query leaves from an address
# the servers can be configured to recognise.

# One dig, printed whole. `+time=2 +tries=1` keeps a query to a server that is
# not answering from blocking a status run for the default 15 seconds.
DIG_COMMON="+time=2 +tries=1"

# Ask one server directly, with recursion switched off, and print the whole
# reply. This is the only way to read what a server is authoritative for: with
# +norecurse the server answers out of its own zones or refers, and never goes
# and looks the name up somewhere else.
dig_direct() {   # <server-address> <name> <type>
    docker exec "$CLIENT_CTN" dig $DIG_COMMON +norecurse "@$1" "$2" "$3" 2>/dev/null
}

# Ask the recursive resolver, which iterates from the root.
dig_resolve() {   # <name> <type>
    docker exec "$CLIENT_CTN" dig $DIG_COMMON "@$CLIENT_IP" "$1" "$2" 2>/dev/null
}

# The flags line of a reply, without the leading ";; flags: " and without the
# section counts: "qr aa rd" and so on. This is where the aa bit is read, which
# is the one bit that separates an authoritative answer from a cached copy of it.
dig_flags() {   # <whole dig output>
    printf '%s\n' "$1" | sed -n 's/^;; flags: \([^;]*\);.*/\1/p' | head -1 \
        | sed 's/[[:space:]]*$//'
}

# A section count out of the reply header: ANSWER, AUTHORITY or ADDITIONAL.
# Anything unparseable becomes 0 rather than the empty string, so an arithmetic
# comparison on the result cannot fail with a syntax error.
dig_count() {   # <whole dig output> <ANSWER|AUTHORITY|ADDITIONAL|QUERY>
    local n
    n="$( printf '%s\n' "$1" | sed -n "s/.*$2: \([0-9]*\).*/\1/p" | head -1 )"
    case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

dig_status() {   # <whole dig output>   -> NOERROR, NXDOMAIN, REFUSED, SERVFAIL, or ""
    printf '%s\n' "$1" | sed -n 's/.*status: \([A-Z]*\).*/\1/p' | head -1
}

# Every answer record of a given type, one rdata per line. An RRset with more
# than one record (a zone's two NS records, say) is returned in a rotating order
# by design, so anything that reads only the first line is reading a value that
# changes between two identical queries.
dig_answer_all() {   # <whole dig output> <type>
    printf '%s\n' "$1" \
        | awk -v t="$2" '
            /^;; ANSWER SECTION:/ { inans = 1; next }
            /^;;/                 { inans = 0 }
            inans && $4 == t      { $1 = $2 = $3 = $4 = ""; sub(/^ +/, ""); print }' \
        | tr -s ' ' | sed 's/[[:space:]]*$//'
}

# The rdata of the first answer record of a given type, with tabs collapsed.
# `dig +short` would be shorter, but it prints nothing at all for a referral,
# which is exactly the case several of this lab's checks need to tell apart from
# an empty answer.
dig_answer_rdata() {   # <whole dig output> <type>
    printf '%s\n' "$1" \
        | awk -v t="$2" '
            /^;; ANSWER SECTION:/ { inans = 1; next }
            /^;;/                 { inans = 0 }
            inans && $4 == t      { $1 = $2 = $3 = $4 = ""; sub(/^ +/, ""); print; exit }' \
        | tr -s ' ' | sed 's/[[:space:]]*$//'
}

# The TTL of the first record of a given type in a named section.
dig_ttl() {   # <whole dig output> <ANSWER|AUTHORITY> <type>
    printf '%s\n' "$1" \
        | awk -v sec=";; $2 SECTION:" -v t="$3" '
            $0 == sec       { ins = 1; next }
            /^;;/           { ins = 0 }
            ins && $4 == t  { print $2; exit }'
}

# One value straight out of a server's own copy of the zone: the SOA serial.
# This is the number the whole of Part 2 turns on, and it is read the same way on
# the primary and on the secondary, so the two can be compared without either
# side being trusted to report its own state.
soa_serial() {   # <server-address> [zone]
    local out
    out="$( dig_direct "$1" "${2:-$ZONE}" SOA )"
    dig_answer_rdata "$out" SOA | awk '{print $3}'
}

# Whether a server answers authoritatively for a name and type: NOERROR, the aa
# bit set, and at least one record in the answer section. All three are needed.
# A server holding no such zone replies REFUSED with aa clear, and a server
# holding the zone but not the name replies NXDOMAIN with aa SET and an empty
# answer, so neither the status nor the flag is sufficient alone.
authoritative_answer() {   # <server-address> <name> <type>
    local out
    out="$( dig_direct "$1" "$2" "$3" )"
    [ "$( dig_status "$out" )" = "NOERROR" ] || return 1
    dig_flags "$out" | grep -qw aa || return 1
    [ "$( dig_count "$out" ANSWER )" -ge 1 ]
}

# Whether a server REFERS a name downwards rather than answering it: NOERROR,
# no answer records, at least one NS in the authority section, and the aa bit
# clear. The clear aa bit is the part worth checking: a referral is the parent
# saying "not mine", and a parent that answered a child's name authoritatively
# would mean the delegation was never made.
is_referral() {   # <server-address> <name> <type>
    local out
    out="$( dig_direct "$1" "$2" "$3" )"
    [ "$( dig_status "$out" )" = "NOERROR" ] || return 1
    [ "$( dig_count "$out" ANSWER )" -eq 0 ] || return 1
    [ "$( dig_count "$out" AUTHORITY )" -ge 1 ] || return 1
    ! dig_flags "$out" | grep -qw aa
}

# The address records a name resolves to through the client's resolver, one per
# line, in the order dig printed them.
resolves_to() {   # <name> <type>
    dig_answer_rdata "$( dig_resolve "$1" "$2" )" "$2"
}

# The number of records a zone transfer returned, or 0 when the server refused
# it. `dig AXFR` prints one line per record, with the zone's SOA at both ends; a
# refusal prints "Transfer failed" and no records at all.
#
# Comment lines AND blank lines are both dropped. dig separates the transfer from
# its trailing statistics with a blank line, and counting those as records
# reports two more than the transfer carried.
axfr_records() {   # <server-address> <zone>
    docker exec "$CLIENT_CTN" dig $DIG_COMMON "@$1" "$2" AXFR 2>/dev/null \
        | tr -d '\r' | grep -v '^;' | grep -c .
}

axfr_refused() {   # <server-address> <zone>
    docker exec "$CLIENT_CTN" dig $DIG_COMMON "@$1" "$2" AXFR 2>&1 \
        | grep -q 'Transfer failed'
}

# named's own view of its configuration, which is what says whether a zone
# statement was accepted rather than merely written. `rndc zonestatus` reports
# the loaded serial and the load time; it fails when named holds no such zone.
zone_is_loaded() {   # <container> <zone>
    docker exec "$1" rndc zonestatus "$2" >/dev/null 2>&1
}

zone_status() {   # <container> <zone>
    docker exec "$1" rndc zonestatus "$2" 2>&1
}

# Whether named is running on a container at all. Every part of the lab depends
# on it, and a learner who wrote a zone file named refuses to load has a stopped
# daemon rather than a bad answer.
named_running() {   # <container>
    docker exec "$1" pgrep -x named >/dev/null 2>&1
}

# Lines from one server's named log. The transfer messages are the ones the lab
# reads: "transfer of ... from ...: Transfer completed" on the secondary, and
# "sending notifies" on the primary.
named_log_grep() {   # <container> <pattern> [count]
    docker exec "$1" sh -c "grep '$2' '$NAMED_LOG' 2>/dev/null | tail -n ${3:-5}" 2>/dev/null \
        | tr -d '\r'
}

# Count matching lines in a server's named log. Anything that is not a plain
# integer becomes 0: `grep -c` prints 0 and exits 1 when it matches nothing, and
# under `set -o pipefail` an `|| echo 0` fires on top of grep's own output and
# yields a two-line string every arithmetic comparison then rejects.
named_log_count() {   # <container> <pattern>
    local n
    n="$( docker exec "$1" sh -c "grep -c '$2' '$NAMED_LOG' 2>/dev/null" 2>/dev/null \
          | tr -d '\r' | head -1 )"
    case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

named_log_tail() {   # <container> [count]
    docker exec "$1" tail -n "${2:-10}" "$NAMED_LOG" 2>/dev/null | tr -d '\r'
}

# Fetch a URL from the client and print the body, or nothing on failure.
fetch() {   # <url>
    docker exec "$CLIENT_CTN" curl -s --max-time 8 "$1" 2>/dev/null | tr -d '\r'
}

fetch_has() {   # <url> <marker>
    fetch "$1" | grep -q "$2"
}

# Whether an address answers an ICMP echo request from the client. Used only on
# the IPv6 address the AAAA record names, to establish that the record points at
# something that is there.
pings6() {   # <address>
    docker exec "$CLIENT_CTN" ping6 -c 2 -W 2 "$1" >/dev/null 2>&1
}

# The chain `dig +trace` walked, one "<zone> <server>" pair per referral it
# followed. This is what makes the delegation visible as a sequence rather than
# as a single answer, and it is the only probe in the lab that reads more than
# one exchange.
trace_zones() {   # <name>
    docker exec "$CLIENT_CTN" dig +trace +tries=1 +time=2 "@$CLIENT_IP" "$1" 2>/dev/null \
        | awk '$4 == "NS" { print $1 }' | uniq
}

# ---------------------------------------------------------------------------
# The lab's definition of done, as data. Each line is
#
#   <server-address> <name> <type> <expected rdata>
#
# and status.sh and selftest.sh both walk it, so there is one place the lab says
# what a finished zone contains. The rdata is matched with a leading-field
# comparison rather than for equality where the record type carries more than the
# value being checked; see check_record below.

# The forward zone, asked of the primary directly.
forward_records() {
    cat <<REC
$PRIMARY_IP $ZONE NS $NS1_NAME.
$PRIMARY_IP $ZONE NS $NS2_NAME.
$PRIMARY_IP $NS1_NAME A $PRIMARY_IP
$PRIMARY_IP $NS2_NAME A $SECONDARY_IP
$PRIMARY_IP $WWW_NAME A $PRIMARY_IP
$PRIMARY_IP $WWW_NAME AAAA $PRIMARY_IP6
$PRIMARY_IP $MAIL_NAME A $SECONDARY_IP
$PRIMARY_IP $ZONE MX $MX_PREFERENCE $MAIL_NAME.
$PRIMARY_IP $WEB_NAME CNAME $WWW_NAME.
$PRIMARY_IP $CLIENT_NAME A $CLIENT_IP
REC
}

# The same set, asked of the secondary. A secondary that transferred the zone
# answers every one of them authoritatively out of its own copy.
secondary_records() {
    forward_records | sed "s/^$PRIMARY_IP /$SECONDARY_IP /"
}

# The child zone, asked of its own server directly.
child_records() {
    cat <<REC
$SUB_IP $CHILD_ZONE NS $CHILD_NS_NAME.
$SUB_IP $CHILD_NS_NAME A $SUB_IP
$SUB_IP $CHILD_WWW_NAME A $SUB_IP
REC
}

# The reverse zone, asked of the primary directly. The owner name of a PTR is the
# address written backwards under in-addr.arpa, which is what these four lines
# are: 115.0.0.10 becomes 10.0.0.115.in-addr.arpa.
reverse_records() {
    cat <<REC
$PRIMARY_IP 10.$REVERSE_ZONE PTR $NS1_NAME.
$PRIMARY_IP 20.$REVERSE_ZONE PTR $NS2_NAME.
$PRIMARY_IP 30.$REVERSE_ZONE PTR $CHILD_NS_NAME.
$PRIMARY_IP 40.$REVERSE_ZONE PTR $CLIENT_NAME.
REC
}

# Check one line of the tables above. Returns 0 when the server answers
# authoritatively and the answer's rdata begins with the expected value.
#
# "Begins with" rather than "equals" because dig prints a record's whole rdata
# and some of it is not what is being checked: an MX line is "10 mail.uni.lab."
# and both fields matter, while a CNAME line is one name and nothing else. A
# prefix comparison covers both without a per-type special case, and it cannot
# pass on a wrong value, only on a value with something extra after it.
check_record() {   # <server-address> <name> <type> <expected rdata...>
    local server="$1" name="$2" type="$3"; shift 3
    local want="$*" out got
    out="$( dig_direct "$server" "$name" "$type" )"
    [ "$( dig_status "$out" )" = "NOERROR" ] || return 1
    dig_flags "$out" | grep -qw aa || return 1
    got="$( dig_answer_all "$out" "$type" )"
    [ -n "$got" ] || return 1
    # Any record in the set may be the one being checked. A zone's NS records are
    # an RRset of more than one, and named rotates the order it prints them in,
    # so matching the first line alone passes or fails at random.
    local line
    while IFS= read -r line; do
        case "$line" in "$want"*) return 0 ;; esac
    done <<< "$got"
    return 1
}

# What a server actually returned for one line of the tables, for status.sh to
# print beside what was wanted. Prints the rdata, or the status when there was no
# answer to print.
actual_record() {   # <server-address> <name> <type>
    local out got
    out="$( dig_direct "$1" "$2" "$3" )"
    got="$( dig_answer_all "$out" "$3" | paste -sd '|' - )"
    if [ -n "$got" ]; then
        printf '%s' "$got"
    else
        printf '(%s)' "$( dig_status "$out" )"
    fi
}
