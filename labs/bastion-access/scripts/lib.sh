#!/usr/bin/env bash
# Shared definitions for the bastion host and access control lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, IPs, interface names, accounts, keys and service ports. Every other
# script sources it; never hardcode any of these in a second place.
#
# The lab is a configuration exercise, not an attack. It hands the learner a site
# where every machine is reachable from outside it and has them narrow that down
# to one path: an operator's workstation reaches a jump host, and only the jump
# host reaches the machines behind it. Three separate mechanisms enforce "only
# from there" and each one lets through something the next one stops, so the
# load-bearing facts here are the three subnets, the one address the inner hosts
# will end up pinned to, and the accounts that hold a key on each machine.

AS=114
DC=LAB

# ---------------------------------------------------------------------------
# Three subnets meeting at one router. Two are point-to-point; the third is
# switched, because the two machines on it have to be able to reach each other
# without crossing the router.
#
#   external : the operator's workstation, and the vantage every port sweep in
#              this lab is run from
#   dmz      : the bastion, alone on a segment of its own. It is the only
#              machine the external segment is ever allowed to open a connection
#              to, and the only machine allowed to open one to the inner segment
#   inner    : the two machines being protected. They share a switch, so a
#              packet from one to the other never reaches the router and no rule
#              the router holds can affect it. That is the whole point of Part 5.
#
# All three live inside the AS's 114.0.0.0/8 block, so subnet_config's AS-octet
# scheme holds and every address is known before a container exists.
EXT_SUBNET="114.0.0.0/24"     # workstation + edge router
DMZ_SUBNET="114.1.0.0/24"     # bastion + edge router
INNER_SUBNET="114.2.0.0/24"   # app + db + edge router, over a switch
PREFIXLEN=24

EDGE_EXT_IP="114.0.0.1"       # edge router, external side  (the workstation's default gateway)
EDGE_DMZ_IP="114.1.0.1"       # edge router, dmz side       (the bastion's default gateway)
EDGE_INNER_IP="114.2.0.1"     # edge router, inner side     (app's and db's default gateway)

WS_IP="114.0.0.10"            # the operator's workstation, outside the site
BASTION_IP="114.1.0.2"        # the jump host; the one address the inner hosts end up trusting
APP_IP="114.2.0.20"           # inner host, runs the site's web service as well as sshd
DB_IP="114.2.0.30"            # inner host, the sensitive one; sshd only

# The edge router forwards between all three segments and, at spawn, filters
# nothing. Everything the lab builds is subtracted from that starting point: the
# learner never opens a path, they close every path but one.

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<segment>
# convention; the router names each of its three NICs after the segment it
# faces. app and db share a segment, so they share an interface name; what
# distinguishes them at the switch is the port name, below.
WS_IF="${AS}-ext"             # workstation's only NIC
BASTION_IF="${AS}-dmz"        # bastion's only NIC
APP_IF="${AS}-inner"          # app's only NIC
DB_IF="${AS}-inner"           # db's only NIC

E_EXT_IF="ext"                # edge router, facing the workstation
E_DMZ_IF="dmz"                # edge router, facing the bastion
E_INNER_IF="inner"            # edge router, facing the switch

# The switch, and the port each inner-segment device lands on. The switch is not
# what this lab is about: it exists so that app, db and the router share one
# broadcast domain, which is what lets app and db reach each other without the
# router seeing the packets.
SW="S1"
SW_CTN="${AS}_L7_${DC}_${SW}"
sw_port_of() { echo "${AS}-$1"; }        # 114-edge, 114-app, 114-db
SWITCH_DEVICES=(edge app db)

# ---------------------------------------------------------------------------
# The ports every sweep covers, in the order status.sh and the handout print
# them. 443 is in the list on purpose and nothing ever listens on it: a port with
# no listener replies with a TCP reset and a port behind a drop rule replies
# nothing at all, and telling those two apart is how the learner reads whether
# the edge router's policy took effect or a service merely stopped.
SSH_PORT=22
WEB_PORT=80
CLOSED_PORT=443
SWEEP_PORTS="${SSH_PORT},${WEB_PORT},${CLOSED_PORT}"

# The web service on app. It is not an SSH service, and that is why it is here:
# a default-deny policy at the edge has to stop it too, so a learner who only
# writes SSH rules can see what they left open.
WEB_MARKER="APP-SITE-7C24E9"
WEB_ROOT="/var/www/localhost/htdocs"

# ---------------------------------------------------------------------------
# Accounts.
#
# The site is delivered with a root password that works over SSH on every
# machine, which is what makes Part 1's direct login possible. Passwords are
# fixed strings rather than generated ones so the handout can name them and the
# oracle can test both the acceptance and, after Part 4, the refusal.
ROOT_PASS="Stavanger-4417"

# One account per machine, and one per job. The bastion's account exists only to
# be jumped through; the two operator accounts each administer one inner host.
# "One key per user" in Part 4 means one key pair per entry in this list, not one
# key the operator reuses everywhere.
JUMP_USER="jump"              # on the bastion
JUMP_PASS="Kirkenes-9302"
APP_USER="appops"             # on app
APP_PASS="Tromso-6158"
DB_USER="dbops"               # on db
DB_PASS="Alesund-3720"

# The forced-command account in Part 5. It exists so a reporting job can read one
# thing off db without holding a shell there, and its authorized_keys entry is
# what makes that true rather than a promise.
REPORT_USER="dbreport"
REPORT_CMD="/usr/local/bin/db-report"
REPORT_MARKER="DB-REPORT-51F8C3"

# Where the workstation keeps the key pairs the operator generates in Part 4. The
# private halves never leave the workstation, until Part 5 has the learner copy
# one onto db on purpose to see what a leaked key can and cannot do.
WS_KEY_DIR="/root/.ssh"
JUMP_KEY="${WS_KEY_DIR}/id_${JUMP_USER}"
APP_KEY="${WS_KEY_DIR}/id_${APP_USER}"
DB_KEY="${WS_KEY_DIR}/id_${DB_USER}"
REPORT_KEY="${WS_KEY_DIR}/id_${REPORT_USER}"

# Where Part 5 has the learner leave a copy of each operator's private key on the
# machine the OTHER operator administers. This is what an operator who keeps one
# workstation for everything and then copies their home directory to a server
# looks like, and the two copies are what make the two restrictions in Part 5
# separately observable: one key ends up pinned and the other does not.
#
# Naming both here is what lets reset.sh remove them. They are learner-created
# state, and a reset that left them behind would start the next run with the
# lateral-movement test already half done.
LEAKED_APP_KEY="/home/${DB_USER}/id_${APP_USER}.leaked"   # appops's key, left on db
LEAKED_DB_KEY="/home/${APP_USER}/id_${DB_USER}.leaked"    # dbops's key, left on app

# ---------------------------------------------------------------------------
# sshd. Each machine's authentication log is half of this lab's oracle: a client
# exit code says a login failed, and this file says why sshd refused it.
#
# `sshd -e` sends the authentication log to stderr, which default_config
# redirects here. The daemon also writes /run/sshd.pid, and that file is the only
# reliable way to reload it: each container's PID 1 is `sleep infinity` under
# Docker's init, and `pgrep -x sshd` lists per-connection children as well as the
# listener, so a HUP aimed by pgrep lands on the wrong process and the reload
# silently does nothing.
SSHD_LOG="/var/log/bastion-sshd.log"
SSHD_PID="/run/sshd.pid"
SSHD_CONFIG="/etc/ssh/sshd_config"

# The nftables table the learner builds on the edge router in Part 2. Named here
# rather than left to the learner so status.sh can find it; the rules inside it
# are entirely their work and are judged by what the sweep reports, not by
# reading the ruleset.
NFT_TABLE="inet filter"
NFT_FORWARD_CHAIN="forward"

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L7 marking the lab's
# layer: <AS>_L7_<DC>_<name>. One prefix covers every container so status and
# teardown select the lab with a single filter.
WS_CTN="${AS}_L7_${DC}_workstation"
EDGE_CTN="${AS}_L7_${DC}_edge"
BASTION_CTN="${AS}_L7_${DC}_bastion"
APP_CTN="${AS}_L7_${DC}_app"
DB_CTN="${AS}_L7_${DC}_db"

# Every device that gets a starter config, in apply order: the router first so
# the three segments are addressed and forwarding before anything crosses them,
# then the machines behind it, then the workstation outside it.
DEVICES=(edge bastion app db workstation)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_bastion"
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

# The state nmap reports for one TCP port, as seen from one container: "open",
# "closed" or "filtered", or the empty string when the scan produced no line for
# that port at all.
#
# -Pn is not optional here. nmap's default host discovery sends probes of its
# own and skips a target it decides is not answering, and the whole point of
# Part 2 is a router that stops answering them on the inner hosts' behalf.
# Without -Pn every sweep after the forward chain is written reports nothing
# rather than reporting drops.
port_state() {   # <from-container> <address> <port>
    docker exec "$1" nmap -Pn -n --host-timeout 20s -p "$3" "$2" 2>/dev/null \
        | awk -v p="$3/tcp" '$1 == p { print $2; exit }'
}

# The whole sweep against one target in one call, printed as "<port> <state>"
# lines. One nmap run rather than three, because three runs against a dropping
# host is three times the retransmit wait.
sweep() {   # <from-container> <address>
    docker exec "$1" nmap -Pn -n --host-timeout 60s -p "$SWEEP_PORTS" "$2" 2>/dev/null \
        | awk '/^[0-9]+\/tcp/ { split($1, a, "/"); print a[1], $2 }'
}

# Fetch a URL from a container and print the body, or nothing on failure.
fetch() {   # <from-container> <url>
    docker exec "$1" curl -s --max-time 8 "$2" 2>/dev/null
}

fetch_has() {   # <from-container> <url> <marker>
    fetch "$1" "$2" | grep -q "$3"
}

# ---------------------------------------------------------------------------
# SSH probes. Every one of them turns off host-key checking and points the known
# hosts file at /dev/null, because a container that was reset now holds a
# different host key under the same address and the check would fail for a reason
# that has nothing to do with what is being tested.

SSH_COMMON=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
            -o ConnectTimeout=8 -o LogLevel=ERROR)

# Try a DIRECT login with a password and report whether it succeeded.
# PreferredAuthentications=password with PubkeyAuthentication=no stops the client
# falling back to a key it happens to hold, so a success here means a password
# really was accepted.
ssh_password_login() {   # <from-container> <user> <password> <address>
    docker exec "$1" sshpass -p "$3" ssh "${SSH_COMMON[@]}" \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no \
        "$2@$4" true >/dev/null 2>&1
}

# What the client printed when a direct password login failed. sshd names the
# methods it is still willing to try, so this line is how the learner reads which
# authentication settings are off.
ssh_password_message() {   # <from-container> <user> <password> <address>
    docker exec "$1" sshpass -p "$3" ssh "${SSH_COMMON[@]}" \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no \
        "$2@$4" true 2>&1 \
        | grep -iE 'permission denied|connection refused|no route|timed out|closed by' \
        | head -1 | tr -d '\r'
}

# Ask the bastion to open a TCP connection to <host>:<port> and print the first
# thing that comes back over it. `ssh -W` connects standard input and output to
# that destination, so against an SSH port the destination's identification
# string arrives with no request sent: it is written by the server on connect.
#
# This is the narrowest possible proof that the jump host forwarded a connection
# and that the connection reached the destination's listener, and it needs only
# ONE password, which is why Part 3's oracle uses it rather than a nested login.
ssh_forward_banner() {   # <from-container> <jump-user> <jump-password> <jump-address> <host> <port>
    docker exec "$1" sh -c "sshpass -p '$3' ssh $( printf '%s ' "${SSH_COMMON[@]}" ) \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no \
        -W '$5:$6' '$2@$4' </dev/null 2>/dev/null | head -c 64" 2>/dev/null | tr -d '\r'
}

# Whether the bastion REFUSED to forward to <host>:<port>. sshd rejects a
# forwarding request that PermitOpen does not list, and the client reports the
# refusal on stderr rather than exiting silently, so both halves are checked:
# nothing came back, and the client said why.
ssh_forward_denied() {   # <from-container> <jump-user> <jump-key> <jump-address> <host> <port>
    local out
    out="$( docker exec "$1" sh -c "ssh -i '$3' $( printf '%s ' "${SSH_COMMON[@]}" ) \
        -o BatchMode=yes -W '$5:$6' '$2@$4' </dev/null 2>&1 | head -c 200" 2>/dev/null )"
    ! printf '%s' "$out" | grep -q 'SSH-2.0'
}

# Run one command on an inner host THROUGH the bastion, authenticating to both
# with keys. -J is OpenSSH's ProxyJump flag: it opens a session to the jump host
# and asks it to forward standard input and output to the final destination,
# which is what makes the final host see the connection as arriving from the
# jump host's own address.
ssh_jump_run() {   # <user> <key> <address> <command...>
    local user="$1" key="$2" addr="$3"; shift 3
    docker exec "$WS_CTN" ssh -i "$key" "${SSH_COMMON[@]}" -o BatchMode=yes \
        -o "ProxyCommand=ssh -i $JUMP_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -W %h:%p ${JUMP_USER}@${BASTION_IP}" \
        "$user@$addr" "$@" 2>/dev/null
}

# True when a key opens a session on an inner host through the bastion.
ssh_jump_login() {   # <user> <key> <address>
    ssh_jump_run "$1" "$2" "$3" true >/dev/null 2>&1
}

# Run one command on an inner host through the bastion and print BOTH streams,
# so a refusal message is readable rather than only an exit code.
ssh_jump_message() {   # <user> <key> <address> <command...>
    local user="$1" key="$2" addr="$3"; shift 3
    docker exec "$WS_CTN" ssh -i "$key" "${SSH_COMMON[@]}" -o BatchMode=yes \
        -o "ProxyCommand=ssh -i $JUMP_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -W %h:%p ${JUMP_USER}@${BASTION_IP}" \
        "$user@$addr" "$@" 2>&1 | head -3
}

# Try a DIRECT key login from one lab container to another, with no jump host in
# the path. This is what Part 5's lateral-movement test runs from db: the same
# key that works through the bastion, used from an address the inner host's
# authorized_keys entry does not permit.
ssh_direct_key_login() {   # <from-container> <user> <key> <address>
    docker exec "$1" ssh -i "$3" "${SSH_COMMON[@]}" -o BatchMode=yes \
        "$2@$4" true >/dev/null 2>&1
}

ssh_direct_key_message() {   # <from-container> <user> <key> <address>
    docker exec "$1" ssh -i "$3" "${SSH_COMMON[@]}" -o BatchMode=yes \
        "$2@$4" true 2>&1 | head -3
}

# ---------------------------------------------------------------------------
# Reading configuration back off a machine.

# The effective value sshd is running with for one keyword, on one container.
# `sshd -T` prints the configuration after every include and default has been
# resolved, in lower case, which is what makes it the right thing to read: the
# file may hold the keyword twice, commented, or not at all, and only the first
# obtained value applies.
#
# This reports what is in the FILE, which is what the learner edited. It is not
# necessarily what the running listener is using: sshd re-reads its configuration
# only on SIGHUP, and a learner who edits and does not reload has a file that
# says one thing and a daemon doing another. status.sh checks both.
sshd_config_value() {   # <container> <keyword>
    local kw
    kw="$( echo "$2" | tr 'A-Z' 'a-z' )"
    docker exec "$1" sh -c "sshd -T 2>/dev/null | awk '\$1 == \"$kw\" { \$1 = \"\"; sub(/^ /, \"\"); print; exit }'"
}

# The effective value sshd resolves for one keyword when the connection comes
# from <address>. `sshd -T -C` evaluates every Match block against the connection
# it describes, which is the only way to read what a Match Address block does
# without opening a connection from that address.
sshd_match_value() {   # <container> <keyword> <source-address> <user>
    local kw
    kw="$( echo "$2" | tr 'A-Z' 'a-z' )"
    docker exec "$1" sh -c "sshd -T -C user=$4,host=$3,addr=$3 2>/dev/null | awk '\$1 == \"$kw\" { \$1 = \"\"; sub(/^ /, \"\"); print; exit }'"
}

# The authorized_keys line for one account, with the key body cut out. What is
# left is the option list, which is the part Part 5 is about: a `from=` pattern,
# a `command=` string, and the no-* restrictions beside them.
# Cutting the key out is done by deleting from the key-type token to the end of
# the line, not by deleting a fixed number of leading fields. An option list may
# contain spaces inside its quotes (command="a b" is legal and common), so
# counting fields from the left gets it wrong the moment a forced command has an
# argument; the key type is the one token whose position is known.
authorized_keys_options() {   # <container> <user>
    authorized_keys_file "$1" "$2" \
        | sed -E 's/ ?(ssh-[a-z0-9-]+|ecdsa-[a-z0-9-]+|sk-[a-z0-9@.-]+) .*$//' \
        | sed '/^$/d'
}

# The whole authorized_keys file for one account, for status.sh to print.
authorized_keys_file() {   # <container> <user>
    docker exec "$1" sh -c "cat \"\$(getent passwd $2 | cut -d: -f6)/.ssh/authorized_keys\" 2>/dev/null"
}

# True when the edge router's packet filter holds a base chain at the forward
# hook whose policy is drop. This is the one structural fact status.sh checks
# about Part 2; which rules sit inside the chain is the learner's work and is
# judged by what the sweep reports, not by reading the ruleset.
forward_policy_is_drop() {
    docker exec "$EDGE_CTN" nft list ruleset 2>/dev/null \
        | grep -qE 'type filter hook forward priority [^;]*; *policy drop'
}

# The edge router's whole ruleset, for status.sh to print.
nft_ruleset() {
    docker exec "$EDGE_CTN" nft list ruleset 2>/dev/null
}

# Count the lines in one machine's authentication log that match a pattern.
# Anything that is not a plain integer becomes 0: `grep -c` prints 0 and exits 1
# when it matches nothing, and under `set -o pipefail` the obvious `|| echo 0`
# fires on top of grep's own output and yields a two-line string that every
# arithmetic comparison then rejects.
sshd_log_count() {   # <container> <pattern>
    local n
    n="$( docker exec "$1" sh -c "grep -c '$2' '$SSHD_LOG' 2>/dev/null" 2>/dev/null \
          | tr -d '\r' | head -1 )"
    case "$n" in
        ''|*[!0-9]*) echo 0 ;;
        *)           echo "$n" ;;
    esac
}

# Lines matching a pattern in one machine's authentication log, most recent last.
sshd_log_grep() {   # <container> <pattern> [count]
    docker exec "$1" sh -c "grep '$2' '$SSHD_LOG' 2>/dev/null | tail -n ${3:-5}"
}

sshd_log_tail() {   # <container> [count]
    docker exec "$1" tail -n "${2:-8}" "$SSHD_LOG" 2>/dev/null
}

# Open a session on an inner host THROUGH the bastion with a password at each
# hop, and print what the command produced. Two passwords means two sshpass
# processes: the outer one answers the final host, and the inner one, inside the
# ProxyCommand, answers the jump host. This is Part 3's oracle, before any key
# exists.
ssh_jump_password_run() {   # <user> <password> <address> <command>
    docker exec "$WS_CTN" sh -c \
        "sshpass -p '$2' ssh $( printf '%s ' "${SSH_COMMON[@]}" ) \
            -o PreferredAuthentications=password -o PubkeyAuthentication=no \
            -o 'ProxyCommand=sshpass -p ${JUMP_PASS} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o PreferredAuthentications=password -o PubkeyAuthentication=no -W %h:%p ${JUMP_USER}@${BASTION_IP}' \
            '$1@$3' '$4'" 2>/dev/null
}

# The source address in the most recent accepted login for one account, read off
# that machine's own authentication log. This is the field every restriction in
# the lab is written against, and the one observation that makes Part 3 and
# Part 5 the same lesson: a session opened through the jump host arrives from the
# jump host's address, not from the operator's.
last_accepted_from() {   # <container> <user>
    docker exec "$1" sh -c "grep 'Accepted .* for $2 from ' '$SSHD_LOG' 2>/dev/null | tail -1" \
        | sed -n 's/.* from \([0-9.]*\) port .*/\1/p'
}
