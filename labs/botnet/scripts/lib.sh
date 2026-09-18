#!/usr/bin/env bash
# Shared definitions for the botnet lab.
# Sourced by spawn/status/shell/advance/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnets, container
# names, addresses, interface names, passwords, the wordlist, the rendezvous
# candidate set and every file path the lab writes. Every other script sources
# it; never hardcode any of these in a second place.
#
# The lab is played from the attacker's side first. A learner installs two bots
# by hand, issues one standing task that makes the population grow itself, uses
# the population for three jobs that are not floods, and then turns round and
# writes the router policy that holds. What makes it an attack is that eight
# machines act on one standing order; every packet any of them sends carries a
# genuine address that passes every source check.
#
# WHICH FIELD HOST HOLDS THE SECOND CREDENTIAL IS AN ANSWER. It is named here
# because a lab script cannot work without it. Nothing the learner is pointed at
# prints it: status.sh reports the roster and the loader's log, both of which
# the learner has already produced, and never the layout of the passwords.

AS=128
LAYER=L4
DC=LAB

# ---------------------------------------------------------------------------
# Three legs on one router.
#
#   inside    the served network: one web and SSH server. What the population
#             is eventually tasked against.
#   field     six ordinary machines, and the network's own admin workstation.
#             This is the population's habitat and the segment it spreads
#             across.
#   operator  the learner's side: the controller and the host that serves the
#             payload.
#
# Three legs rather than two, because the whole defensive argument depends on
# which of the botnet's traffic a policy at the router can see. Recruitment,
# tasking and payload delivery all cross the router. Spread from one field host
# to the next does not: it stays on one switch, and no rule the learner writes
# at the router can touch it.
#
# The router FORWARDS and does not translate addresses, so every packet still
# carries the address of the machine that sent it. Behind a NAT the whole
# exercise would collapse to one source address.
INSIDE_SUBNET="128.0.0.0/24"
FIELD_SUBNET="128.1.0.0/24"
OPERATOR_SUBNET="128.2.0.0/24"
PREFIXLEN=24

R_INSIDE_IP="128.0.0.1"
R_FIELD_IP="128.1.0.1"
R_OP_IP="128.2.0.1"

# --- inside ----------------------------------------------------------------
SERVER_IP="128.0.0.20"

# --- field -----------------------------------------------------------------
#
# The addresses are scattered rather than consecutive, so a learner who finds
# one host cannot guess the next and has to sweep the segment. The admin's
# workstation sits among them because that is where a staff machine sits: it
# runs no sshd, so nothing the botnet does ever recruits it, and its two probe
# jobs both cross the router, which is what makes it the lab's collateral
# damage check.
HOST1_IP="128.1.0.42"
HOST2_IP="128.1.0.13"
HOST3_IP="128.1.0.68"
HOST4_IP="128.1.0.27"
HOST5_IP="128.1.0.88"
HOST6_IP="128.1.0.53"
ADMIN_IP="128.1.0.77"

FIELD_HOSTS=(host1 host2 host3 host4 host5 host6)

# --- operator --------------------------------------------------------------
C2_IP="128.2.0.10"           # where the learner starts the controller
C2_ALT_IP="128.2.0.58"       # a second address on the same container; see below
LOADER_IP="128.2.0.40"

C2_PORT=8080
LOADER_PORT=80
WEB_PORT=80
SSH_PORT=22

# ---------------------------------------------------------------------------
# The credential layout, and the half-finished rotation behind it.
#
# Four field hosts still share one root password, because the site's credential
# rotation stopped halfway. Two were done early and hold a password that is on
# no wordlist. The record of which is which is a file left on one of the four
# that did not get rotated, which is how the harvest pays for the next round of
# propagation.
#
# PW_WAVE1 is the password the handout gives the learner for the two hand
# installs in Part 1. PW_WAVE2 is the one the harvest returns.
PW_WAVE1="Harbour-2019"
PW_WAVE2="Ptarmigan-Vault-7731"

# host2 and host5 are the two the handout has the learner install by hand.
# host1 and host4 fall to the standing task, which is what takes the population
# from two to four. host3 and host6 hold PW_WAVE2 and are what advance.sh
# recruits once the harvest has returned it.
WAVE1_HOSTS=(host1 host2 host4 host5)
WAVE2_HOSTS=(host3 host6)
HAND_HOSTS=(host2 host5)

# The host whose loot file names PW_WAVE2 and the two addresses it opens. An
# answer; see the header.
LOOT_HOST=host4
LOOT_FILE="/srv/ops/migration-notes.txt"

# ---------------------------------------------------------------------------
# The inside server's accounts.
#
# SERVER_USER is what the distributed guessing task is aimed at, and its
# password is word WORDLIST_HIT of the wordlist below. SYSOPS_USER is the
# account the admin workstation logs in with every ADMIN_SSH_INTERVAL seconds;
# it is a separate account with a password on no list, so changing what the
# botnet is guessing does not break the admin, and so the admin's own SSH
# remains the reason tcp/22 toward the server cannot simply be switched off.
SERVER_USER="opsadmin"
SERVER_PW="Kestrel-Marsh-88"
SERVER_ROOT_PW="Quarry-Lintel-5540"
SYSOPS_USER="sysops"
SYSOPS_PW="Foxglove-Tarn-6182"

# The wordlist the loader serves, in order. Forty candidates; SERVER_PW is
# number WORDLIST_HIT. The population splits the list by round robin, so with n
# bots the shard holding entry k reaches it on its ceil(k/n)-th attempt: with
# six bots and the hit at 36, one bot reaches it on its sixth attempt and the
# whole population has made about 36 attempts by then. That is the arithmetic
# question 9 asks for, and the reason the list is this length.
WORDLIST=(
    "summer2019"       "Password1"        "letmein"          "harbour"
    "Harbour2019"      "admin123"         "opsadmin"         "changeme"
    "Autumn-2020"      "qwerty123"        "Server!2020"      "welcome1"
    "P@ssw0rd"         "Marsh-2018"       "kestrel"          "Kestrel2018"
    "backup2019"       "Ops-Team-1"       "Winter-2021"      "trustno1"
    "Harbour-2018"     "Sysops-9"         "monitoring"       "Kestrel-Marsh"
    "Kestrel-Marsh-86" "lighttpd"         "Marsh-88"         "Harbour-2020"
    "Spring-2022"      "Kestrel-88"       "opsadmin2019"     "Quarry-1"
    "Marsh-Kestrel-88" "Kestrel_Marsh_88" "kestrel-marsh-88" "Kestrel-Marsh-88"
    "Lintel-2021"      "Tarn-1990"        "Foxglove-1"       "Vault-7731"
)
WORDLIST_HIT=36                  # 1-based index of SERVER_PW in WORDLIST
WORDLIST_PATH="/var/www/localhost/htdocs/words.txt"
WORDLIST_URL="http://${LOADER_IP}/words.txt"

# The per-bot interval the handout has the learner choose for the guessing
# task, in seconds, and the connect timeout each attempt uses. Both are named
# here so selftest.sh and the answer key cannot disagree with the handout.
#
# GUESS_CONNECT_TIMEOUT is no longer spelled on any command line. It is the
# ConnectTimeout in /etc/ssh/ssh_config.d/10-minilabs.conf, which image/Dockerfile
# writes into every lab container so that an ssh in this lab needs no -o flags.
# A Dockerfile cannot source this file, so the value exists in both places and
# selftest.sh stage 2 reads it back out of a running container and fails if the
# two have drifted apart, the same way it compares C2_CANDIDATES with bot.py.
GUESS_INTERVAL=5
GUESS_CONNECT_TIMEOUT=4
GUESS_OUT="/tmp/guess.out"

# The per-source cap Part 4's second move applies, expressed the way iptables
# spells it. Two new connections a minute per source leaves the admin's own
# login, one every sixty seconds, untouched.
CAP_RATE="2/min"
CAP_BURST=2
CAP_NAME="sshcap"

# ---------------------------------------------------------------------------
# The payload, the controller, and the rendezvous candidate set.
#
# The bot holds eight candidate controller addresses on the operator leg,
# shuffles them on every pass and connects to the first that accepts. Two of
# them are the controller's container, which holds C2_IP and C2_ALT_IP at once;
# the other six are assigned to nothing, so a connection to one of them times
# out. That layout is what Part 4's fourth move is built on: a learner who
# blocks the address they started the controller on is correct, and the
# population comes back through the other one inside one pass.
#
# A pass is therefore at most eight connection attempts, and with
# BOT_CONNECT_TIMEOUT at two seconds it takes at most sixteen seconds. That
# bound is load-bearing: the sixty-four candidate pool the COMPX316 demo used
# takes over two minutes a pass, which is longer than anybody will sit and
# watch for a registration.
C2_CANDIDATES=(
    "128.2.0.10" "128.2.0.17" "128.2.0.23" "128.2.0.34"
    "128.2.0.47" "128.2.0.58" "128.2.0.66" "128.2.0.85"
)
C2_CANDIDATE_COUNT=8
BOT_CONNECT_TIMEOUT=2
BOT_PASS_WAIT=5                  # seconds between fruitless full passes
BOT_MAX=8                        # the controller refuses registrations past this

BOT_PATH="/tmp/bot.py"
BOT_URL="http://${LOADER_IP}/bot.py"
BOT_SRC="/var/www/localhost/htdocs/bot.py"
BOT_PIDFILE="/run/minilabs/bot.pid"
BOT_LOG="/var/log/minilabs-bot.log"

# The marker file the payload refuses to run without. It is written into the
# lab image and exists nowhere else, so bot.py is inert on any machine that is
# not a container of this lab. See the Safety note in the handout.
LAB_MARKER="/etc/minilabs-lab"

# The bound on how long one task may run, and the cap on what it may return. A
# command that outruns BOT_CMD_TIMEOUT is killed and reported with exit 124;
# output past BOT_RESULT_CAP bytes is discarded. The bound is minutes, not
# seconds: the distributed-guessing task in Part 3 walks a wordlist shard at a
# rate the learner chooses and legitimately takes a minute or two, and a
# guessing task that never finds its target (after the credentials are fixed in
# Part 4) is meant to be killed by this bound rather than to run forever. It
# still frees a genuinely wedged bot, just not in thirty seconds.
BOT_CMD_TIMEOUT=120
BOT_RESULT_CAP=4096

# The distributed guessing task's shape, referenced by the handout, the answer
# key and selftest so none of them can drift. Each bot tries GUESS_CHUNK words
# of the wordlist starting at (its own field octet mod 40), wrapping at the end.
# 12 words per bot over a 40-word list means the population covers the list with
# redundancy, so the account still falls if one bot never joined, and the word
# the account actually uses (index WORDLIST_HIT-1) is reached by two bots rather
# than one. Each source therefore makes at most GUESS_CHUNK attempts, which is
# what keeps any single source's auth-log footprint small (question 10).
GUESS_CHUNK=12

# ---------------------------------------------------------------------------
# The controller's state on disk. The controller keeps its roster in memory and
# writes these files on every change, which is what lets status.sh report the
# population without opening a socket to a process the learner is typing into.
C2_DIR="/var/lib/c2"
C2_ROSTER="${C2_DIR}/roster.tsv"
C2_RESULTS="${C2_DIR}/results"
C2_TASKFILE="${C2_DIR}/standing-task"
C2_LOG="/var/log/c2.log"
C2_CTL="/run/minilabs/c2.ctl"    # the unix socket `c2 -c <command>` sends to
C2_PIDFILE="/run/minilabs/c2.pid"

# The loader's access log: the recruitment record, and the only place that says
# in what order the population was built. Part 4's last question turns on it.
LOADER_LOG="/var/log/lighttpd/access.log"

# The server's authentication log. sshd runs with -e and its stderr is
# redirected here, so every failed password carries the source address it came
# from, which is the field every rule in Part 4's first two moves is written
# against.
SERVER_AUTH_LOG="/var/log/minilabs-sshd.log"
SERVER_WEB_LOG="/var/log/lighttpd/access.log"

# The admin workstation's two probe jobs and the files they write. The web
# probe is the fast one, so a policy that breaks the served page shows up
# within seconds; the SSH probe is the slow one, and its period is what the cap
# in Part 4's second move has to stay clear of.
ADMIN_WEB_INTERVAL=5
ADMIN_SSH_INTERVAL=60
ADMIN_WEB_STATE="/var/lib/minilabs/admin-web.state"
ADMIN_SSH_STATE="/var/lib/minilabs/admin-ssh.state"
ADMIN_WEB_PID="/run/minilabs/probe-web.pid"
ADMIN_SSH_PID="/run/minilabs/probe-ssh.pid"

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<switch>
# convention, so a machine's interface says which leg it is on. The router
# holds one of each.
IF_INSIDE="${AS}-S1"
IF_FIELD="${AS}-S2"
IF_OP="${AS}-S3"

# One switch per leg. Three bridges inside one switch container would behave
# identically -- they are three broadcast domains and do not forward between
# each other -- but would draw as a single box every machine connects to, and
# the one fact this lab is built on is that the only path between legs is the
# router.
SWITCHES=(S1 S2 S3)
SW_INSIDE_CTN="${AS}_${LAYER}_${DC}_S1"
SW_FIELD_CTN="${AS}_${LAYER}_${DC}_S2"
SW_OP_CTN="${AS}_${LAYER}_${DC}_S3"
BR="br0"
sw_port_of() { echo "${AS}-$1"; }        # 128-server, 128-host1, 128-c2, ...

# ---------------------------------------------------------------------------
# Container names: <AS>_<LAYER>_<DC>_<name>. The field hosts are host1 to host6
# and carry no role in their names, because `docker ps` and the node list are
# things a learner sees before they have scanned anything.
ROUTER_CTN="${AS}_${LAYER}_${DC}_router"
SERVER_CTN="${AS}_${LAYER}_${DC}_server"
ADMIN_CTN="${AS}_${LAYER}_${DC}_admin"
C2_CTN="${AS}_${LAYER}_${DC}_c2"
LOADER_CTN="${AS}_${LAYER}_${DC}_loader"

ctn_of() { echo "${AS}_${LAYER}_${DC}_$1"; }

# Every device that gets a starter config, in apply order: the router first so
# there is a path between the legs, then the loader and the server so there is
# something to fetch and something to attack, then the field hosts, then the
# admin whose probe jobs start last and immediately have somewhere to probe.
# The c2 gets a config too, and it starts nothing: the controller is a program
# the learner runs.
DEVICES=(router loader c2 server host1 host2 host3 host4 host5 host6 admin)

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

pw_of() {   # <field host role> -> the root password it boots with
    local h
    for h in "${WAVE2_HOSTS[@]}"; do
        [ "$h" = "$1" ] && { echo "$PW_WAVE2"; return 0; }
    done
    echo "$PW_WAVE1"
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_botnet"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed". --no-mlockall is
# what makes this lab boot on a rootless daemon.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it.
#
# An image is otherwise only rebuilt when it is missing, which means an edit to
# image/bot.py never reaches a machine that built the image once: the loader
# keeps serving the previous payload and the handout describes a bot the
# learner does not have.
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
# Shared read-only probes. status.sh, advance.sh and selftest.sh all need
# these, and a second copy of any of them is a chance for the three to disagree
# about what the lab's state is.

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# --- the controller's side -------------------------------------------------

c2_running() {
    docker exec "$C2_CTN" sh -c "test -S '$C2_CTL'" >/dev/null 2>&1
}

# Send one operator command to a running controller and print its reply. This
# is the same path the learner's own REPL takes; `c2 -c` connects to the socket
# the controller listens on beside its bot port.
c2_cmd() {   # <command line>
    docker exec "$C2_CTN" c2 -c "$1" 2>/dev/null
}

# The roster, one bot per line, as the controller last wrote it:
#   <id> <address> <hostname> <first seen> <last seen> <last seq> <last exit>
roster_lines() {
    docker exec "$C2_CTN" sh -c "cat '$C2_ROSTER' 2>/dev/null" 2>/dev/null
}

bot_count() {
    roster_lines | grep -c . || true
}

# The addresses in the roster, one per line, in registration order. The
# recruitment order is a graded observable, so this preserves it rather than
# sorting.
bot_addresses() {
    roster_lines | awk '{ print $2 }'
}

# How many result bodies the controller holds for a given task sequence number,
# counting only the non-empty ones. With no argument, every result on disk.
result_count() {   # [seq]
    local pat="*"
    [ $# -ge 1 ] && pat="$1"
    docker exec "$C2_CTN" sh -c \
        "find '$C2_RESULTS' -type f -name '*.${pat}.txt' -size +0 2>/dev/null | wc -l" 2>/dev/null \
        | tr -dc '0-9'
}

# The sequence number of the standing task, or 0 when there is none. The seq is
# the FIRST field of the task file's first line; the rest of the line is the
# shell command, which may itself contain digits (a `head -20`, an address), so
# this must read field one and not every digit on the line.
standing_seq() {
    docker exec "$C2_CTN" sh -c "head -1 '$C2_TASKFILE' 2>/dev/null" 2>/dev/null | awk '{ print $1 + 0 }'
}

# True when any result body the controller holds contains the second credential.
# The harvest is graded on this, and it is read from the controller rather than
# from the host that leaked it: the question is not whether the file exists, it
# is whether the population brought it back.
loot_has_pw2() {
    docker exec "$C2_CTN" sh -c "grep -rqF '$PW_WAVE2' '$C2_RESULTS' 2>/dev/null"
}

# --- the loader's side -----------------------------------------------------

# How many times the payload has been fetched. This is the recruitment counter,
# and it counts requests for bot.py alone: the wordlist is served from the same
# document root and a fetch of it is not a recruitment.
payload_fetches() {
    docker exec "$LOADER_CTN" sh -c \
        "grep -c 'GET /bot.py' '$LOADER_LOG' 2>/dev/null" 2>/dev/null | tr -dc '0-9'
}

# One line per payload fetch: the time and the address that asked for it. The
# recruitment order comes off this, and so does the gap between a fetch and the
# registration that follows it.
payload_fetch_log() {
    docker exec "$LOADER_CTN" sh -c \
        "grep 'GET /bot.py' '$LOADER_LOG' 2>/dev/null" 2>/dev/null
}

# --- the inside server's side ----------------------------------------------

# True when SERVER_USER has been authenticated over SSH from a field address.
# This is the headline oracle for the guessing task, and it is read from the
# server's own log rather than from a bot: the question a cap answers is not
# whether the population tried, it is whether anything got in.
account_guessed() {
    docker exec "$SERVER_CTN" sh -c \
        "grep -q 'Accepted password for ${SERVER_USER} from 128\\.1\\.' '$SERVER_AUTH_LOG' 2>/dev/null"
}

# Epoch seconds of the first successful guess, or "" when there has been none.
# selftest.sh subtracts a start time from this to get the time to compromise.
guessed_at() {
    docker exec "$SERVER_CTN" sh -c \
        "grep -m1 'MINILABS-GUESSED' '$SERVER_AUTH_LOG' 2>/dev/null" 2>/dev/null \
        | awk '{ print $1 }' | tr -dc '0-9'
}

# How many password failures the server has logged, and how many of them came
# from each field address. The per-source counts are what Part 4's first move
# is written from.
failed_attempts() {
    docker exec "$SERVER_CTN" sh -c \
        "grep -c 'Failed password for' '$SERVER_AUTH_LOG' 2>/dev/null" 2>/dev/null | tr -dc '0-9'
}

failed_by_source() {
    docker exec "$SERVER_CTN" sh -c \
        "grep 'Failed password for' '$SERVER_AUTH_LOG' 2>/dev/null" 2>/dev/null \
        | grep -oE 'from [0-9.]+' | awk '{ print $2 }' | sort | uniq -c | sort -rn
}

# --- the admin workstation's side ------------------------------------------
#
# Each probe writes one line to its state file every time it runs: the epoch
# second, then ok or fail, then what it saw. Reading the file rather than
# running a fresh probe is deliberate: it says whether the network worked for
# the admin while the learner was typing, not whether it works now.

admin_web_state() { docker exec "$ADMIN_CTN" sh -c "cat '$ADMIN_WEB_STATE' 2>/dev/null" 2>/dev/null; }
admin_ssh_state() { docker exec "$ADMIN_CTN" sh -c "cat '$ADMIN_SSH_STATE' 2>/dev/null" 2>/dev/null; }

admin_web_ok() { admin_web_state | grep -q ' ok '; }
admin_ssh_ok() { admin_ssh_state | grep -q ' ok '; }

# --- the router's side -----------------------------------------------------

# The filter table as the learner wrote it, in the form iptables-save prints,
# which is the form a learner can paste back. Empty when they have written
# nothing.
router_rules() {
    docker exec "$ROUTER_CTN" iptables -S FORWARD 2>/dev/null | grep -v '^-P FORWARD'
}

router_rule_count() {
    router_rules | grep -c . || true
}

# --- waiters ---------------------------------------------------------------
#
# Nothing in this lab is instantaneous. A bot registers seconds after the
# command that installs it, a recruited host fetches the payload before it
# registers, and a task result comes back when the command finishes. Every
# script waits on a condition with a timeout rather than sleeping: a sleep long
# enough to be safe makes a fourteen-stage selftest unbearable.

# Wait until the roster holds at least <n> bots.
wait_for_bots() {   # <n> <timeout seconds>
    local want="$1" deadline=$(( $( date +%s ) + $2 ))
    while [ "$( date +%s )" -lt "$deadline" ]; do
        [ "$( bot_count )" -ge "$want" ] && return 0
        sleep 1
    done
    return 1
}

# Wait until the roster stops changing for <quiet> consecutive seconds, so a
# caller can measure a population that has finished growing rather than one
# caught mid-cascade.
wait_for_bots_settled() {   # <quiet seconds> <timeout seconds>
    local quiet="$1" deadline=$(( $( date +%s ) + $2 )) last stable=0
    last="$( bot_count )"
    while [ "$( date +%s )" -lt "$deadline" ]; do
        sleep 1
        local now; now="$( bot_count )"
        if [ "$now" = "$last" ]; then
            stable=$(( stable + 1 ))
            [ "$stable" -ge "$quiet" ] && return 0
        else
            stable=0; last="$now"
        fi
    done
    return 1
}

# Wait until a file exists inside a container and is non-empty.
wait_for_file() {   # <container> <path> <timeout seconds>
    local deadline=$(( $( date +%s ) + $3 ))
    while [ "$( date +%s )" -lt "$deadline" ]; do
        docker exec "$1" sh -c "test -s '$2'" >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# Wait until a shell condition inside a container succeeds.
wait_for_cmd() {   # <timeout seconds> <command...>
    local deadline=$(( $( date +%s ) + $1 )); shift
    while [ "$( date +%s )" -lt "$deadline" ]; do
        "$@" >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# Wait until the controller holds at least <n> non-empty results for <seq>.
wait_for_results() {   # <seq> <n> <timeout seconds>
    local deadline=$(( $( date +%s ) + $3 ))
    while [ "$( date +%s )" -lt "$deadline" ]; do
        [ "$( result_count "$1" )" -ge "$2" ] && return 0
        sleep 1
    done
    return 1
}
