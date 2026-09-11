#!/usr/bin/env bash
# Shared definitions for the centralised logging and incident reconstruction lab.
# Sourced by spawn/status/shell/reset/incident/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnet, container
# names, IPs, interface names, accounts, file paths and markers. Every other
# script sources it; never hardcode any of these in a second place.
#
# The lab is a configuration exercise with a forensic second half. Four machines
# share one switched segment: three that produce log messages and one that is
# meant to collect them. At spawn each of the three writes its messages to a file
# on its own disk and sends them nowhere, which is a site where the record of an
# event lives only on the machine the event happened to. The learner builds the
# forwarding, the per-host destination files and the rotation policy, and then an
# incident runs and the local copy on one of the three is deleted.

AS=113
DC=LAB
SW=S1

# ---------------------------------------------------------------------------
# One flat segment. Nothing in this lab is about routing or about Layer 2: every
# machine is one hop from every other, so a message that does not arrive at the
# collector failed for a reason in the logging configuration and never for a
# reason in the network.
SUBNET="113.0.0.0/24"
PREFIXLEN=24

COLLECTOR_IP="113.0.0.10"   # the log server
ADMIN_IP="113.0.0.20"       # the administrator's workstation
WEB_IP="113.0.0.30"         # the public web service
DB_IP="113.0.0.40"          # the sensitive host, and the one whose local log is deleted

# ---------------------------------------------------------------------------
# Interface names. Every machine plugs into the same switch, so they all follow
# the platform's <AS>-<SW> convention and every device has exactly one NIC.
HOST_IF="${AS}-${SW}"

# The switch names each port after the device on the other end of it.
sw_port_of() { echo "${AS}-$1"; }

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L7 marking the lab's
# layer: syslog is an application protocol and every machine in the lab is an end
# host. The switch carries the same prefix so status and teardown select the
# whole lab with a single filter.
COLLECTOR_CTN="${AS}_L7_${DC}_collector"
ADMIN_CTN="${AS}_L7_${DC}_admin"
WEB_CTN="${AS}_L7_${DC}_web"
DB_CTN="${AS}_L7_${DC}_db"
SW_CTN="${AS}_L7_${DC}_${SW}"

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

# Every device, in the order spawn configures them: the collector first, so a
# source host that starts forwarding early has somewhere to forward to.
DEVICES=(collector admin web db)

# The three machines that produce the messages the lab is about. The collector is
# not one of them, and keeping the two lists apart is what lets a script ask
# "did every SOURCE arrive" without counting the collector's own messages.
SOURCES=(admin web db)

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_log"
SWITCH_IMAGE="miniinterneteth/d_switch"

# ovs-ctl rather than the image's supervisord entrypoint, and --no-mlockall
# rather than the default: under a rootless daemon CAP_IPC_LOCK cannot exceed
# RLIMIT_MEMLOCK, thread stacks fail to lock, and ovs-vswitchd dies with
# pthread_create failed before the bridge ever exists.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# The syslog transport. 514 is the port for both the UDP and the TCP transport;
# the lab uses TCP, and the handout has the learner see the one-character
# difference in the rsyslog rule that selects between them.
SYSLOG_PORT=514

# Where each machine writes what it produces itself. Deleting this file on the
# machine an event happened to is what the last part of the lab is about, so it
# is named once rather than typed into four scripts.
LOCAL_LOG="/var/log/messages"

# Where the collector is meant to put what it receives, one file per source host.
# The directory exists from spawn and is empty; the rule that fills it is the
# learner's to write.
REMOTE_DIR="/var/log/remote"

# rsyslog's own files. The base configuration is delivered by the starter
# configs; every rule the learner writes goes in a drop-in under RSYSLOG_D,
# because that is where a distribution puts local additions and because it keeps
# reset.sh's undo to "delete the drop-ins".
RSYSLOG_CONF="/etc/rsyslog.conf"
RSYSLOG_D="/etc/rsyslog.d"
RSYSLOG_PID="/var/run/rsyslogd.pid"

# The two drop-ins the learner creates, named here so status.sh can report on
# them by the same paths the handout tells the learner to type.
FORWARD_CONF="${RSYSLOG_D}/50-forward.conf"
RECEIVE_CONF="${RSYSLOG_D}/10-receive.conf"

# The rotation policy, and logrotate's own state file. logrotate records the last
# rotation of every path it manages in the state file, which is why a second
# `logrotate` run with no `-f` does nothing.
LOGROTATE_CONF="/etc/logrotate.d/remote"
LOGROTATE_STATE="/var/lib/logrotate.status"

# ---------------------------------------------------------------------------
# Accounts. Both are ordinary unprivileged users with a password, because the
# events the lab reconstructs are password authentications and OpenSSH records a
# failed password attempt only when password authentication is offered.
#
# The passwords are in a lab script and in the answer key and nowhere else. They
# are not secrets; they are the input to an authentication the lab needs to
# succeed on the seventh attempt and fail on the first six.
DB_USER="dbadmin"
DB_PASS="Th4mesRiver!"
ADMIN_USER="ops"
ADMIN_PASS="Wint3rMoss?"

# The six wrong passwords the incident tries before the right one. Six is a
# number the handout tells the learner to count for themselves, so it is fixed
# here and emitted by selftest.sh as an observation rather than being written
# into the handout as prose.
WRONG_PASSWORDS=(hunter2 letmein Password1 dbadmin123 qwerty admin)
FAILED_ATTEMPTS=${#WRONG_PASSWORDS[@]}

# ---------------------------------------------------------------------------
# The web service on `web`. It logs through syslog rather than to a file of its
# own, which is what puts a second facility and a second program name in the
# collector's files beside sshd's, and gives the learner something to tell apart.
WEB_PORT=80
WEB_ROOT="/var/www/localhost/htdocs"
WEB_MARKER="WEB-SITE-5A71C9"
LIGHTTPD_CONF="/etc/lighttpd/lighttpd.conf"

# The path the incident's HTTP requests ask for. It does not exist, so lighttpd
# records a 404 against it, which is a real status code for a real request and
# not a fabricated log line.
WEB_PROBE_PATH="/admin/backup.tar.gz"

# ---------------------------------------------------------------------------
# The probe status.sh sends from each source host to decide whether forwarding
# works. It carries a facility and a severity that nothing else in the lab uses,
# so a line carrying this marker at the collector can only have come from the
# probe, and the facility and severity recorded beside it can be compared against
# what was asked for.
PROBE_FACILITY="local5"
PROBE_SEVERITY="notice"
PROBE_MARKER="MINILABS-PROBE-8F2D6E"

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

# Image preflight, called by spawn.sh before the first `docker run`.
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
# created in never matters. Asking for the host's namespace (--network=host) only
# breaks the helper under a rootless daemon, where that namespace belongs to a
# user namespace the helper holds no privilege in and every `ip link add` returns
# EPERM. --pid=host stays: it is what makes each lab container's
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
# Shared read-only probes. status.sh, incident.sh and selftest.sh all need these,
# and a second copy of any of them is a chance for them to disagree about what
# the lab's success condition is.

# Run a command on a lab device by role name.
on() {   # <role> <cmd...>
    local role="$1"; shift
    docker exec "$( ctn_of "$role" )" "$@"
}

# The path the collector is meant to be writing <role>'s messages to. The
# per-host file is named after the HOSTNAME field the sender put in the message,
# and every container is started with --hostname set to its role name, so the two
# agree by construction.
remote_file_of() {   # <role>
    printf '%s/%s.log' "$REMOTE_DIR" "$1"
}

# Every line the collector holds for <role>, live file only. The rotated copies
# are deliberately not included: a question about what survived a rotation has to
# be able to distinguish the two.
remote_lines() {   # <role>
    docker exec "$COLLECTOR_CTN" sh -c "cat '$( remote_file_of "$1" )' 2>/dev/null"
}

# Every line the collector holds for <role> including the rotated and compressed
# copies, oldest first. This is what an investigator actually reads, because an
# incident older than the last rotation is not in the live file at all.
remote_lines_all() {   # <role>
    local f; f="$( remote_file_of "$1" )"
    docker exec "$COLLECTOR_CTN" sh -c \
        "for n in 9 8 7 6 5 4 3 2 1; do
             [ -f '$f'.\$n.gz ] && gzip -dc '$f'.\$n.gz
             [ -f '$f'.\$n ]    && cat '$f'.\$n
         done
         cat '$f' 2>/dev/null" 2>/dev/null
}

# How many lines carrying <pattern> the collector holds for <role>, across the
# live file and every rotated copy.
#
# The grep runs inside the container and its result is captured before it is
# tested. A `docker exec ... | grep -c` pipeline looks equivalent and is not:
# under `set -o pipefail` a docker exec killed by SIGPIPE is read as a failure of
# the whole pipeline.
remote_count() {   # <role> <pattern>
    local n
    n="$( remote_lines_all "$1" | grep -c -- "$2" 2>/dev/null | tr -d '\r' )"
    case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

# Every line <role> holds in its OWN local file. Empty after the incident on the
# machine the incident deleted it from, which is the whole point of the last part.
local_lines() {   # <role>
    docker exec "$( ctn_of "$1" )" sh -c "cat '$LOCAL_LOG' 2>/dev/null"
}

local_count() {   # <role> <pattern>
    local n
    n="$( local_lines "$1" | grep -c -- "$2" 2>/dev/null | tr -d '\r' )"
    case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

# True when <role>'s local log file exists at all. A file that is absent and a
# file that is present and empty are different outcomes and the lab distinguishes
# them: the incident removes the file, and rsyslog recreates it on the next
# message it writes.
local_log_exists() {   # <role>
    docker exec "$( ctn_of "$1" )" test -f "$LOCAL_LOG"
}

# Send one probe message from <role> and give the collector a moment to write it.
# This is a measurement, not a configuration change: it is the same `logger`
# command the handout has the learner type, and it is the only way to find out
# whether a forwarding rule works without waiting for the machine to say
# something of its own accord.
send_probe() {   # <role> [suffix]
    docker exec "$( ctn_of "$1" )" logger \
        -p "${PROBE_FACILITY}.${PROBE_SEVERITY}" "${PROBE_MARKER}${2:+ $2}"
}

# Send probes from <role> until one of them reaches the collector, or give up.
# Prints the token the successful probe carried, so a caller can find that exact
# line; prints nothing and returns non-zero when none of them arrived.
#
# <where> selects which file at the collector counts as arrival. Before the
# per-host ruleset exists, everything that arrives is written into the
# collector's own /var/log/messages along with the collector's own messages, so
# "did it arrive" and "is it in its own file" are two different questions and
# only one of them has a yes at that point in the lab.
#
# The retry is not padding, and the window has to be wider than it looks. A
# forwarding action whose TCP connection was broken by a restart of the collector
# is suspended, and rsyslog DISCARDS what it is handed while an action is
# suspended rather than holding it: the default action.resumeRetryCount is 0, and
# the documentation states plainly that failed actions discard messages. It is
# retried only once the resume interval elapses, and action.resumeInterval
# defaults to 30 seconds and grows by itself after repeated failures. So a probe
# window shorter than 30 seconds answers "is forwarding working" with a no on a
# lab that is working perfectly well, and does it intermittently, which is worse
# than doing it always.
#
# One attempt is 10 seconds, so the default of 6 covers a minute.
probe_arrives() {   # <role> [where: perhost|own] [attempts]
    local role="$1" where="${2:-perhost}" attempts="${3:-6}" i j token n
    for i in $( seq 1 "$attempts" ); do
        token="PROBE-$$-${i}"
        send_probe "$role" "$token" >/dev/null 2>&1
        for j in $( seq 1 10 ); do
            if [ "$where" = "own" ]; then
                n="$( local_count collector "$token" )"
            else
                n="$( remote_count "$role" "$token" )"
            fi
            if [ "$n" -ge 1 ]; then
                printf '%s' "$token"
                return 0
            fi
            sleep 1
        done
    done
    return 1
}

# True when the collector has a listener on the syslog port.
collector_listening() {
    local hit
    hit="$( docker exec "$COLLECTOR_CTN" sh -c \
        "netstat -tln 2>/dev/null | grep -c ':${SYSLOG_PORT} '" | tr -d '\r' )"
    case "$hit" in ''|0|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# True when <role>'s rsyslog configuration, drop-ins included, carries <text>.
config_has() {   # <role> <substring>
    local hit
    hit="$( docker exec "$( ctn_of "$1" )" sh -c \
        "cat '$RSYSLOG_CONF' ${RSYSLOG_D}/*.conf 2>/dev/null | grep -c -F -- '$2'" | tr -d '\r' )"
    case "$hit" in ''|0|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# The rsyslog process id <role> is running under, empty when it is not running.
# Read from the pid file rather than from `pgrep`, because it is the same value
# the learner's own postrotate script reads and a mismatch between the two is
# itself worth surfacing.
rsyslog_pid() {   # <role>
    docker exec "$( ctn_of "$1" )" sh -c "cat '$RSYSLOG_PID' 2>/dev/null" | tr -d '\r'
}

rsyslog_running() {   # <role>
    docker exec "$( ctn_of "$1" )" sh -c 'pgrep -x rsyslogd >/dev/null 2>&1'
}

# Restart rsyslog on <role>, which is what a configuration change needs. A HUP
# makes rsyslog close and reopen its output files and does NOT re-read the
# configuration, so a drop-in added since the daemon started has no effect until
# the daemon is replaced. Both facts are in the handout and this is the path the
# lab scripts use.
#
# The wait and the pid-file removal are both load-bearing. rsyslogd refuses to
# start while its pid file names a live process, and it does not remove that file
# until it has finished shutting down; a fixed `sleep` before starting the
# replacement is a race that a busy machine loses, and the failure it produces
# ("pidfile and pid already exist", exit -3000) leaves the machine running its
# OLD configuration while every script that asked for a restart reports success.
rsyslog_restart() {   # <role>
    docker exec "$( ctn_of "$1" )" sh -c "
        pkill -x rsyslogd >/dev/null 2>&1
        n=0
        while pgrep -x rsyslogd >/dev/null 2>&1 && [ \$n -lt 40 ]; do
            sleep 0.25; n=\$(( n + 1 ))
        done
        rm -f '$RSYSLOG_PID'
        rsyslogd" || true
}

# Which files the collector holds under the per-host directory, one per line,
# names only.
remote_dir_listing() {
    docker exec "$COLLECTOR_CTN" sh -c "ls -1 '$REMOTE_DIR' 2>/dev/null"
}

# The mode of a path on <role>, as four octal digits. logrotate refuses to read a
# configuration file that is group- or world-writable, and `docker exec` runs
# with umask 0022 under a rootful daemon and 0000 under a rootless one, so this
# is a value that differs between two machines running the same commands.
mode_of() {   # <role> <path>
    docker exec "$( ctn_of "$1" )" sh -c "stat -c '%a' '$2' 2>/dev/null" | tr -d '\r'
}

# ---------------------------------------------------------------------------
# The incident's own signatures, named once so status.sh, selftest.sh and the
# answer key cannot disagree about what the learner is looking for. Each is the
# text OpenSSH itself writes; none of them is a string this lab invents.
FAIL_SIGNATURE="Failed password for ${DB_USER} from ${WEB_IP}"
ACCEPT_SIGNATURE="Accepted password for ${DB_USER} from ${WEB_IP}"
ROUTINE_SIGNATURE="Accepted password for ${DB_USER} from ${ADMIN_IP}"
LATERAL_SIGNATURE="Accepted password for ${ADMIN_USER} from ${DB_IP}"
