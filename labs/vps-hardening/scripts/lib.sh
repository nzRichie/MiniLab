#!/usr/bin/env bash
# Shared definitions for the VPS provisioning and hardening lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, interface names, service ports and credentials. Every other script
# sources it; never hardcode any of these in a second place.
#
# The lab is a configuration exercise, not an attack. It hands the learner a
# server as a hosting provider delivers one — root reachable over SSH with a
# password, three services on every address it holds, no packet filter — and has
# them close each of those in turn. The load-bearing facts here are therefore the
# three service ports, the two addresses a service may end up bound to, and the
# one subnet SSH is allowed to come from.

AS=110
DC=LAB

# ---------------------------------------------------------------------------
# Three subnets, one router between all of them. Each is a point-to-point link:
# every segment holds exactly one host, so there is no switch and no broadcast
# domain to share.
#
#   external   : the host outside the site, and the vantage every port sweep in
#                this lab is run from
#   server     : the machine being hardened, and the only device the learner
#                writes configuration on
#   management : the administrative client, the one source SSH is meant to be
#                reachable from once the lab is finished
#
# All three live inside the AS's 110.0.0.0/8 block, so subnet_config's AS-octet
# scheme holds and every address is known before a container exists.
EXT_SUBNET="110.0.0.0/24"     # outside host + router
SRV_SUBNET="110.1.0.0/24"     # server + router
MGMT_SUBNET="110.2.0.0/24"    # admin station + router
PREFIXLEN=24

ROUTER_EXT_IP="110.0.0.1"     # router, external side    (the outside host's default gateway)
ROUTER_SRV_IP="110.1.0.1"     # router, server side      (the server's default gateway)
ROUTER_MGMT_IP="110.2.0.1"    # router, management side  (the admin station's default gateway)

OUTSIDE_IP="110.0.0.10"       # outside the site; reaches the server only through the router
SERVER_IP="110.1.0.20"        # the machine the learner hardens
ADMIN_IP="110.2.0.30"         # the administrative client

# The router routes all three segments and filters nothing. That is deliberate
# and it is what makes the server's own configuration the whole of its defence:
# the outside host can put a packet in front of every port the server holds,
# including the SSH port, so an address being "on the management subnet" stops
# nothing by itself. Something on the server has to enforce it.

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<segment>
# convention; the router names each of its three NICs after the segment it
# faces.
OUT_IF="${AS}-ext"            # outside host's only NIC
SRV_IF="${AS}-srv"            # server's only NIC
ADMIN_IF="${AS}-mgmt"         # admin station's only NIC

R_EXT_IF="ext"                # router, facing the outside host
R_SRV_IF="srv"                # router, facing the server
R_MGMT_IF="mgmt"              # router, facing the admin station

# ---------------------------------------------------------------------------
# The three services the server answers on when it is delivered, and the one
# port nothing listens on. That fourth port is in the sweep on purpose: a port
# with no listener answers with a TCP reset and a port behind a drop rule
# answers nothing, and telling those two apart is what the sweep is read for.
SSH_PORT=22
WEB_PORT=80
ADMIN_PORT=8080
CLOSED_PORT=443

# Every port the sweep covers, in the order status.sh and the handout print them.
SWEEP_PORTS="${SSH_PORT},${WEB_PORT},${CLOSED_PORT},${ADMIN_PORT}"

# ---------------------------------------------------------------------------
# Credentials.
#
# ROOT_PASS is what the server is delivered with: a root account reachable over
# SSH with a password from anywhere that can route to it. Part 1 has the learner
# use it once, from the outside host, to see that it works; Part 3 is what stops
# it. It is a fixed string rather than a generated one so the handout can name it
# and the oracle can test the refusal.
ROOT_PASS="Trondheim-5182"

# The administrative account the learner creates in Part 2, and the password they
# give it. The password is fixed in the handout for the same reason: `sudo` asks
# for it, so the answer key and the oracle both have to know it. Once Part 3 has
# run it is no longer an SSH credential at all — it authenticates the learner to
# `sudo` on a session the key already opened.
ADMIN_USER="opsadmin"
ADMIN_PASS="Bergen-7734"

# The group `sudo` is configured against. Alpine ships /etc/sudoers with the
# %wheel line commented out, and `wheel` already exists as a group, so putting
# the account in it and uncommenting one line is the whole of Part 2's privilege
# work.
SUDO_GROUP="wheel"

# Where the admin station keeps the key pair it authenticates with. The private
# key never leaves this container; the public half is what the learner installs
# on the server.
ADMIN_KEY="/root/.ssh/id_ed25519"

# ---------------------------------------------------------------------------
# The two web services, and the marker each one serves. Both markers are
# distinctive strings that appear nowhere else in the lab, so finding one in a
# fetch is unambiguous evidence of which service answered.
#
#   PUBLIC_MARKER  is served on WEB_PORT and must still be reachable from
#                  outside when the lab is finished. A learner who hardens the
#                  server by making its public service unreachable has not
#                  hardened it.
#   ADMIN_MARKER   is served on ADMIN_PORT by a second lighttpd instance. It
#                  ships bound to 0.0.0.0, which is the mistake Part 4 is about.
PUBLIC_MARKER="PUBLIC-SITE-4B71A0"
ADMIN_MARKER="ADMIN-STATUS-D93E17"

PUBLIC_WEB_ROOT="/var/www/localhost/htdocs"
ADMIN_WEB_ROOT="/var/www/admin"

# The second lighttpd instance's own config, pid file and log directory. It needs
# all three of its own: two instances sharing a pid file leave the second one
# unable to say which process to stop.
#
# The log directory has to be owned by the lighttpd account rather than by root.
# lighttpd opens its error log AFTER dropping privileges to server.username, so a
# directory this lab created as root makes the instance exit at startup with
# "opening errorlog ... failed: Permission denied" and take no port at all.
ADMIN_CONF="/etc/lighttpd/admin.conf"
ADMIN_PID="/run/lighttpd-admin.pid"
ADMIN_LOG_DIR="/var/log/lighttpd-admin"
LIGHTTPD_USER="lighttpd"

# ---------------------------------------------------------------------------
# sshd's authentication log, which is half of this lab's oracle: the outside
# host's exit code says a login failed, and this file says why sshd refused it.
#
# `sshd -e` sends the authentication log to stderr, which default_config
# redirects here. The daemon also writes /run/sshd.pid, and that file is the only
# reliable way to reload it: this container's PID 1 is `sleep infinity` under
# Docker's init, and `pgrep -x sshd` lists per-connection children as well as the
# listener, so a HUP aimed by pgrep lands on the wrong process and the reload
# silently does nothing.
SSHD_LOG="/var/log/vps-sshd.log"
SSHD_PID="/run/sshd.pid"
SSHD_CONFIG="/etc/ssh/sshd_config"

# The nftables table the learner builds in Part 5. Named rather than left to the
# learner so status.sh can find it; the rules inside it are entirely their work.
NFT_TABLE="inet filter"
NFT_CHAIN="input"

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L7 marking the lab's
# layer: <AS>_L7_<DC>_<name>. One prefix covers every container so status and
# teardown select the lab with a single filter.
ROUTER_CTN="${AS}_L7_${DC}_router"
SERVER_CTN="${AS}_L7_${DC}_server"
ADMIN_CTN="${AS}_L7_${DC}_admin"
OUTSIDE_CTN="${AS}_L7_${DC}_outside"

# Every device that gets a starter config, in apply order: the router first so
# the three segments are addressed and forwarding before anything crosses them,
# then the server, then the two clients.
DEVICES=(router server admin outside)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_vps"

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

# Image preflight, called by spawn.sh before the first `docker run`. This lab
# runs no switch, so its own host image is the only one to build.
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

# The state nmap reports for one TCP port, as seen from one container: "open",
# "closed" or "filtered", or the empty string when the scan produced no line for
# that port at all.
#
# -Pn is not optional here. nmap's default host discovery sends probes of its
# own and skips a target it decides is not answering, and the whole point of
# Part 5 is a server that stops answering them. Without -Pn every sweep after
# the packet filter is written reports nothing rather than reporting drops.
port_state() {   # <from-container> <address> <port>
    docker exec "$1" nmap -Pn -n --host-timeout 20s -p "$3" "$2" 2>/dev/null \
        | awk -v p="$3/tcp" '$1 == p { print $2; exit }'
}

# The whole sweep in one call, printed as "<port> <state>" lines. One nmap run
# rather than four, because four runs of nmap against a dropping host is four
# times the retransmit wait.
sweep() {   # <from-container> <address>
    docker exec "$1" nmap -Pn -n --host-timeout 60s -p "$SWEEP_PORTS" "$2" 2>/dev/null \
        | awk '/^[0-9]+\/tcp/ { split($1, a, "/"); print a[1], $2 }'
}

# True when the named TCP port on the server has a listener bound to <address>.
# Read from the server's own socket table rather than from a probe, because the
# question Part 4 asks is which address the service bound, and a probe from
# another host cannot distinguish "bound elsewhere" from "filtered".
listens_on() {   # <address> <port>
    docker exec "$SERVER_CTN" netstat -tln 2>/dev/null \
        | awk -v want="$1:$2" '$1 == "tcp" && $4 == want { found = 1 } END { exit !found }'
}

# Every listening TCP socket on the server, as "<address>:<port>" lines. What
# status.sh prints so a learner can see what is bound where without shelling in.
listeners() {
    docker exec "$SERVER_CTN" netstat -tln 2>/dev/null \
        | awk '$1 == "tcp" { print $4 }' | sort -u
}

# Fetch a URL from a container and print the body, or nothing on failure.
fetch() {   # <from-container> <url>
    docker exec "$1" curl -s --max-time 8 "$2" 2>/dev/null
}

# True when the fetch returned the marker it should have.
fetch_has() {   # <from-container> <url> <marker>
    fetch "$1" "$2" | grep -q "$3"
}

# Try an SSH login with a PASSWORD and report whether it succeeded. Used only to
# prove a refusal: after Part 3 every call of this must fail.
#
# PreferredAuthentications=password stops the client falling back to a key it
# happens to hold, so a success here means a password really was accepted.
ssh_password_login() {   # <from-container> <user> <password> <address>
    docker exec "$1" sshpass -p "$3" ssh \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no \
        -o ConnectTimeout=8 -o LogLevel=ERROR \
        "$2@$4" true >/dev/null 2>&1
}

# What the client printed when a password login failed. sshd names the methods it
# is still willing to try, so this line is how the learner reads which of the
# three authentication settings are off.
ssh_password_message() {   # <from-container> <user> <password> <address>
    docker exec "$1" sshpass -p "$3" ssh \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no \
        -o ConnectTimeout=8 -o LogLevel=ERROR \
        "$2@$4" true 2>&1 | grep -i 'permission denied' | head -1
}

# Run one command over SSH with the admin station's KEY, and print its output.
ssh_key_run() {   # <address> <command...>
    local addr="$1"; shift
    docker exec "$ADMIN_CTN" ssh -i "$ADMIN_KEY" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR \
        "${ADMIN_USER}@${addr}" "$@" 2>/dev/null
}

# True when the admin station can open a session with its key.
ssh_key_login() {   # <address>
    ssh_key_run "$1" true >/dev/null 2>&1
}

# Run one command through `sudo` over that session, feeding sudo the account's
# password on stdin. Prints the command's output.
ssh_sudo_run() {   # <address> <command string>
    docker exec "$ADMIN_CTN" ssh -i "$ADMIN_KEY" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR \
        "${ADMIN_USER}@${1}" "echo '${ADMIN_PASS}' | sudo -S -p '' $2" 2>/dev/null
}

# Open an SSH tunnel from the admin station to <target> on the server, fetch
# through it, and print what came back. Prints nothing when the server refused
# the forward.
#
# The local port is fixed rather than chosen, so a leftover tunnel from an
# earlier call is closed rather than silently reused: every call kills any ssh
# the admin station is still running first. `pkill -x ssh` matches the process
# name exactly; a pattern match on the command line would match the shell this
# runs in, whose own arguments contain the string.
TUNNEL_LOCAL_PORT=18080
ssh_tunnel_fetch() {   # <server address> <target host:port on the server> <path>
    docker exec "$ADMIN_CTN" sh -c "pkill -x ssh 2>/dev/null; sleep 0.3
        ssh -i '$ADMIN_KEY' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR \
            -f -N -L ${TUNNEL_LOCAL_PORT}:${2} '${ADMIN_USER}@${1}' 2>/dev/null
        sleep 1
        curl -s --max-time 6 'http://127.0.0.1:${TUNNEL_LOCAL_PORT}${3}' 2>/dev/null
        pkill -x ssh 2>/dev/null" 2>/dev/null
}

# True when the server's packet filter holds a base chain at the input hook whose
# policy is drop. This is the one structural fact status.sh checks about Part 5;
# which rules sit inside the chain is the learner's work and is judged by what
# the sweep reports, not by reading the ruleset.
input_policy_is_drop() {
    docker exec "$SERVER_CTN" nft list ruleset 2>/dev/null \
        | grep -qE 'type filter hook input priority [^;]*; *policy drop'
}

# The server's whole ruleset, for status.sh to print.
nft_ruleset() {
    docker exec "$SERVER_CTN" nft list ruleset 2>/dev/null
}

# Count the lines in sshd's authentication log that match a pattern. Anything
# that is not a plain integer becomes 0: `grep -c` prints 0 and exits 1 when it
# matches nothing, and under `set -o pipefail` the obvious `|| echo 0` fires on
# top of grep's own output and yields a two-line string that every arithmetic
# comparison then rejects.
sshd_log_count() {   # <pattern>
    local n
    n="$( docker exec "$SERVER_CTN" sh -c "grep -c '$1' '$SSHD_LOG' 2>/dev/null" 2>/dev/null \
          | tr -d '\r' | head -1 )"
    case "$n" in
        ''|*[!0-9]*) echo 0 ;;
        *)           echo "$n" ;;
    esac
}

# The last few lines of sshd's authentication log, for status.sh to print.
sshd_log_tail() {   # <count>
    docker exec "$SERVER_CTN" tail -n "${1:-8}" "$SSHD_LOG" 2>/dev/null
}

# The effective value sshd is running with for one keyword. `sshd -T` prints the
# configuration after every include and default has been resolved, in lower case,
# which is what makes it the right thing to read: the file may hold the keyword
# twice, commented, or not at all, and only the first obtained value applies.
#
# This reports what is in the FILE, which is what the learner edited. It is not
# necessarily what the running listener is using: sshd re-reads its configuration
# only on SIGHUP, and a learner who edits and does not reload has a file that
# says one thing and a daemon doing another. status.sh checks both.
sshd_config_value() {   # <keyword>
    docker exec "$SERVER_CTN" sh -c "sshd -T 2>/dev/null | awk '\$1 == \"$( echo "$1" | tr 'A-Z' 'a-z' )\" { \$1 = \"\"; sub(/^ /, \"\"); print; exit }'"
}
