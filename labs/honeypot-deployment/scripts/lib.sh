#!/usr/bin/env bash
# Shared definitions for the honeypot deployment lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, interface names and credentials. Every other script sources it;
# never hardcode any of these in a second place.
#
# The lab is about where a decoy sits and what it is allowed to reach, so the
# load-bearing facts here are the four subnets, which of them the router treats
# as trusted, and the two addresses the redirect maps between.

AS=106
DC=LAB

# ---------------------------------------------------------------------------
# Four subnets, one router between all of them. Each is a point-to-point link:
# every segment in this lab holds exactly one host, so there is no switch and no
# broadcast domain to share. The segmentation the lab teaches is enforced at the
# router, which is the only device that sees traffic between two segments.
#
#   external   : where the attacker sits, outside everything it attacks
#   production : the protected host, the one that must stay untouched
#   honeypot   : the decoy's own segment, separate from production by design
#   management : the admin station, whose access has to survive the defence
#
# All four live inside the AS's 106.0.0.0/8 block, so subnet_config's AS-octet
# scheme still holds and every address is known before a container exists.
EXT_SUBNET="106.0.0.0/24"     # attacker + router
PROD_SUBNET="106.1.0.0/24"    # production host + router
HONEY_SUBNET="106.2.0.0/24"   # honeypot + router
MGMT_SUBNET="106.3.0.0/24"    # admin station + router
PREFIXLEN=24

ROUTER_EXT_IP="106.0.0.1"     # router, attacker side    (the attacker's default gateway)
ROUTER_PROD_IP="106.1.0.1"    # router, production side  (prod's default gateway)
ROUTER_HONEY_IP="106.2.0.1"   # router, honeypot side    (the honeypot's default gateway)
ROUTER_MGMT_IP="106.3.0.1"    # router, management side  (admin's default gateway)

ATTACKER_IP="106.0.0.10"      # outside; reaches production only through the router
PROD_IP="106.1.0.20"          # the protected host: real sshd, real web service
HONEY_IP="106.2.0.10"         # the decoy
ADMIN_IP="106.3.0.30"         # the management station

# ---------------------------------------------------------------------------
# Cowrie refuses to run as root, and an unprivileged process cannot bind a port
# below 1024, so the honeypot listens on 2222 while the service it impersonates
# listens on 22. That gap is why the redirect the learner writes in Part 2
# rewrites a port as well as an address. The second half of that holds only
# because spawn.sh sets net.ipv4.ip_unprivileged_port_start to 1024; Docker's
# own default is 0, under which the cowrie account binds 22 without complaint.
SSH_PORT=22
HONEY_SSH_PORT=2222
WEB_PORT=80

# ---------------------------------------------------------------------------
# Cowrie's outbound guard, and why this lab's addressing is what makes Part 3
# work at all.
#
# cowrie/core/network.py refuses to fetch from any address its _is_blocked()
# call rejects, and fakes a DNS resolution failure rather than admitting it
# blocked anything. That check rejects every address for which Python's
# ipaddress.is_global is false, which includes all of RFC 1918. A lab built on
# 10.0.0.0/8 or 192.168.0.0/16 would therefore have its Part 3 pivot silently
# refused by the honeypot itself, and the handout would be describing something
# the learner can never observe.
#
# 106.0.0.0/8 is globally routable, so the guard permits it and the honeypot
# really does fetch from the production host. This is a property of the
# AS-octet addressing scheme rather than a workaround, but it is load-bearing:
# do not renumber this lab into private space.
#
# The other half of that trade is the isolation invariant. These addresses are
# real APNIC space, so a container that could route off the host would reach the
# real internet instead of the lab. No lab container has a default route off the
# host: every interface is a veth whose far end is another lab container, and
# status.sh asserts it.

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<peer> convention;
# the router names each of its four NICs after the segment it faces, because the
# defence is written per-segment and a rule that names the wrong one is the most
# likely mistake a learner makes.
ATT_IF="${AS}-ext"            # attacker's only NIC
PROD_IF="${AS}-prod"          # production host's only NIC
HONEY_IF="${AS}-honey"        # honeypot's only NIC
ADMIN_IF="${AS}-mgmt"         # admin station's only NIC

R_EXT_IF="ext"                # router, facing the attacker
R_PROD_IF="prod"              # router, facing production
R_HONEY_IF="honey"            # router, facing the honeypot
R_MGMT_IF="mgmt"              # router, facing management

# ---------------------------------------------------------------------------
# The credential the attacker arrives holding, framed in the handout as recovered
# from an earlier engagement. Part 1 is not a password attack: the point of this
# lab starts after the attacker is already inside, so the credential is handed
# over rather than guessed.
#
# The same pair is what the learner teaches the honeypot to accept in Part 2, so
# the attacker's second attempt succeeds exactly as its first one did and it has
# no way to tell from the login itself that anything changed.
LAB_USER="netadmin"
LAB_PASS="Rotterdam-4417"

# The two markers the oracles grep for. Both are distinctive strings that appear
# nowhere else in the lab, so finding one in a capture is unambiguous evidence
# that the data behind it moved.
#
#   PROD_SECRET  sits in a file only an SSH session on the production host can
#                read; the attacker reads it in Part 1 and never again.
#   PROD_DOC     is served by production's web service; it is what the attacker
#                reaches in Part 3 by making the honeypot fetch it, and what the
#                containment rule stops.
PROD_SECRET="PROD-HANDOVER-9F2C41"
PROD_DOC="INTERNAL-ROUTING-PLAN-77D3E8"

PROD_SECRET_FILE="/srv/internal/handover.txt"
PROD_DOC_PATH="/internal.html"
PROD_WEB_ROOT="/var/www/localhost/htdocs"

# Where Cowrie lives on the honeypot, and the log the capture oracle reads.
# cowrie.json is Cowrie's own JSON output engine, enabled by default in
# cowrie.cfg.dist; every session event lands there one JSON object per line.
COWRIE_HOME="/opt/cowrie"
COWRIE_BIN="/opt/cowrie-venv/bin"
COWRIE_USER="cowrie"
COWRIE_JSON="${COWRIE_HOME}/var/log/cowrie/cowrie.json"
COWRIE_CFG="${COWRIE_HOME}/etc/cowrie.cfg"
COWRIE_USERDB="${COWRIE_HOME}/etc/userdb.txt"

# Production's web access log, the second half of the Part 3 oracle: it records
# the source address of whatever fetched the document, which is the honeypot's
# address when the pivot works and nothing at all when the containment holds.
PROD_ACCESS_LOG="/var/log/lighttpd/access.log"
# Production's auth log, the Part 2 oracle: sshd -e logs authentication to
# stderr, which spawn redirects here, so a successful attacker login on the real
# host leaves a line and a redirected one leaves none.
PROD_AUTH_LOG="/var/log/prod-sshd.log"

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L7 marking the lab's
# layer: <AS>_L7_<DC>_<name>. One prefix covers every container so status and
# teardown select the lab with a single filter.
ROUTER_CTN="${AS}_L7_${DC}_router"
ATTACKER_CTN="${AS}_L7_${DC}_attacker"
PROD_CTN="${AS}_L7_${DC}_prod"
HONEY_CTN="${AS}_L7_${DC}_honeypot"
ADMIN_CTN="${AS}_L7_${DC}_admin"

# Every device that gets a starter config, in apply order: the router first so
# forwarding and the edge filter are up before anything crosses it, then the
# hosts, attacker last.
DEVICES=(router prod honeypot admin attacker)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_honey"

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# only rebuilt when it is missing, which means an edit to image/Dockerfile never
# reaches a machine that built the image once: the container keeps running the
# previous version and the handout describes a honeypot the learner does not
# have.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

# Image preflight, called by spawn.sh before the first `docker run`. This lab
# runs no switch, so its own host image is the only one to build. Docker caches
# it, so every spawn after the first is a no-op here unless image/ has changed.
ensure_images() {
    if ! docker image inspect "$HOST_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] building $HOST_IMAGE from $LAB_DIR/image (first run only; Cowrie makes this a few minutes)"
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

# ---------------------------------------------------------------------------
# Shared read-only probes. status.sh and selftest.sh both need these, and a
# second copy of any of them is a chance for the two to disagree about what the
# lab's success condition is.

# True when Cowrie is listening on the honeypot.
cowrie_running() {
    docker exec "$HONEY_CTN" netstat -tln 2>/dev/null \
        | grep -qE "[:.]${HONEY_SSH_PORT} +.*LISTEN"
}

# True when the router currently redirects hostile SSH to the honeypot.
redirect_active() {
    docker exec "$ROUTER_CTN" nft list ruleset 2>/dev/null \
        | grep -q "dnat to ${HONEY_IP}:${HONEY_SSH_PORT}"
}

# Run a counting command in a container and print a single integer, always.
#
# `grep -c` prints 0 and exits 1 when it matches nothing, and every caller here
# runs under `set -o pipefail`, so the obvious `... || echo 0` fires on top of
# grep's own output and yields the two-line string "0\n0". Every arithmetic
# comparison against that then fails with "integer expected", and the stage
# reports the lab broken when it is only the counter that is. Anything that is
# not a plain integer becomes 0 here instead.
_count_in() {   # <ctn> <shell command that prints a count>
    local n
    n="$( docker exec "$1" sh -c "$2 2>/dev/null" 2>/dev/null | tr -d '\r' | head -1 )"
    case "$n" in
        ''|*[!0-9]*) echo 0 ;;
        *)           echo "$n" ;;
    esac
}

# Count the commands Cowrie has captured across every session it has logged.
cowrie_command_count() {
    _count_in "$HONEY_CTN" "grep -c '\"eventid\":\"cowrie.command.input\"' '$COWRIE_JSON'"
}

# Print every command Cowrie captured, one per line, newest last.
cowrie_commands() {
    docker exec "$HONEY_CTN" sh -c \
        "grep -o '\"input\":\"[^\"]*\"' '$COWRIE_JSON' 2>/dev/null | sed 's/^\"input\":\"//; s/\"$//'" \
        2>/dev/null || true
}

# Count successful logins Cowrie has recorded.
cowrie_login_count() {
    _count_in "$HONEY_CTN" "grep -c 'cowrie.login.success' '$COWRIE_JSON'"
}

# Count successful SSH logins on the REAL production host. This is the number
# that must stop growing once the redirect is in place.
prod_login_count() {
    _count_in "$PROD_CTN" "grep -c 'Accepted password' '$PROD_AUTH_LOG'"
}

# Count times production's web service has served the INTERNAL DOCUMENT to the
# honeypot. Non-zero means the pivot in Part 3 got through; zero means the
# containment held.
#
# Scoped to that one path rather than to every request from the honeypot, because
# status.sh's own reachability probe fetches "/" from the same host. Counting all
# of them would mean a learner who ran Status twice saw the number this lab is
# about go up on its own.
prod_fetches_from_honeypot() {
    _count_in "$PROD_CTN" "grep -c '^${HONEY_IP} .*GET ${PROD_DOC_PATH}' '$PROD_ACCESS_LOG'"
}
