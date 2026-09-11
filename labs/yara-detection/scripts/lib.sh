#!/usr/bin/env bash
# Shared definitions for the YARA rule authoring and generalisation lab.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnet, container
# names, IPs, interface names, corpus paths and pass marks. Every other script
# sources it; never hardcode any of these in a second place.
#
# The lab is played as a detection engineer rather than as an attacker and then
# a defender. A corpus of thirty Windows executables sits on the workstation,
# eight of them builds of one implant family and twenty-two of them benign. The
# learner writes a YARA rule that separates the two, and the rule is then scored
# against ten files the learner has never seen.
#
#   Part 1  a rule keyed on one build's whole configuration block
#   Part 2  the packed builds, and what compression leaves behind
#   Part 3  the holdout, where every single-feature rule has a false positive
#   Part 4  deployment: the scanner in front of the upload endpoint
#
# Nothing here executes a sample. PE code does not run on Linux, so the corpus
# is inert by construction, and no lab script ever invokes one of the files.

AS=126
DC=LAB

# ---------------------------------------------------------------------------
# One segment, four hosts, one switch. Nothing in this lab crosses a router:
# what is being taught is a file format and a rule language, and the only
# traffic on the wire is the two uploads Part 4 sends.
SUBNET="126.0.0.0/24"
PREFIXLEN=24

WORKSTATION_IP="126.0.0.10"   # the analysis box; every rule is written here
SCANNER_IP="126.0.0.20"       # the upload endpoint Part 4 deploys to
CLIENT_IP="126.0.0.30"        # posts the two files to the scanner
HOLDOUT_IP="126.0.0.40"       # the scoring appliance; no service listens on it

LAN_IF="${AS}-lan"            # the interface name inside every container

# Container names follow the platform convention, with L7 marking the lab's
# layer: <AS>_L7_<DC>_<name>. The subject is a file format and an application
# protocol, not routing.
WORKSTATION_CTN="${AS}_L7_${DC}_workstation"
SCANNER_CTN="${AS}_L7_${DC}_scanner"
CLIENT_CTN="${AS}_L7_${DC}_client"
HOLDOUT_CTN="${AS}_L7_${DC}_holdout"
SW_CTN="${AS}_L7_${DC}_S1"

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

# Every device that gets a starter config, in apply order. The holdout is
# configured first because it is the one machine nothing else waits on, and the
# scanner before the client that posts to it.
DEVICES=(holdout workstation scanner client)

# The roles shell.sh prints a docker exec line for. The holdout is deliberately
# absent: it holds the ten files Part 3 is scored against, and no path the
# handout describes leads into it.
SHELL_ROLES=(workstation scanner client)

BR=br0
sw_port_of() { echo "${AS}-$1"; }

ip_of() {   # <role> -> the address the handout names it by
    case "$1" in
        workstation) echo "$WORKSTATION_IP" ;;
        scanner)     echo "$SCANNER_IP" ;;
        client)      echo "$CLIENT_IP" ;;
        holdout)     echo "$HOLDOUT_IP" ;;
        *)           echo "" ;;
    esac
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# Two images from one Dockerfile, built with --target. The split is what keeps
# the holdout out of reach: the analysis image the learner has three shells into
# carries the corpus and no holdout sample, and the holdout image carries the
# ten holdout samples and no shell the handout ever names.
HOST_IMAGE="d_host_yara"
HOLDOUT_IMAGE="d_host_yara_hold"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed". --no-mlockall is what
# makes this lab boot on a rootless daemon.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# Where everything lives.
#
# The corpus is two directories because Part 1 and Part 2 scan different sets:
# set-a is the twenty unpacked files Part 1 works on, and set-b is the ten Part
# 2 adds, three of which are packed family builds. `yara -r` over CORPUS_DIR
# reads both.
CORPUS_DIR="/srv/corpus"
CORPUS_SET_A="${CORPUS_DIR}/set-a"
CORPUS_SET_B="${CORPUS_DIR}/set-b"
HOLDOUT_DIR="/srv/holdout"
HOLDOUT_TRUTH="${HOLDOUT_DIR}/.truth"

# The file the learner writes, and the one status.sh reads. Everything the lab
# scores comes out of this path on the workstation.
RULES_FILE="/root/rules.yar"

# What the learner deploys to the scanner in Part 4, and where the CGI reads it
# from. The pristine CGI is reinstalled from the image on every spawn and reset.
DEPLOYED_DB="/etc/minilabs/deployed.yar"
CGI_PRISTINE="/usr/local/lib/minilabs/upload.cgi"
CGI_DIR="/var/www/cgi-bin"
CGI_FILE="${CGI_DIR}/upload.cgi"
WEBROOT="/var/www"
LIGHTTPD_CONF="/etc/lighttpd/scanner.conf"
LIGHTTPD_PID="/run/lighttpd.pid"
UPLOAD_URL="http://${SCANNER_IP}/cgi-bin/upload.cgi"

# The two files the client posts. One is a packed build of the family; the other
# is the benign triage helper that carries the family's tag as a literal string,
# which is what stops a rule keyed on the tag alone from passing this stage.
UPLOAD_DIR="/root/uploads"
UPLOAD_PRISTINE="/usr/local/share/minilabs/uploads"
UPLOAD_MALICIOUS="invoice-viewer.exe"
UPLOAD_BENIGN="logtag-check.exe"

# ---------------------------------------------------------------------------
# The family, and the one string every build of it opens its configuration
# block with. The handout gives the tag no earlier than the learner can find it
# with pestr; it is here because status.sh, selftest.sh and the answer key all
# have to agree on what the corpus contains.
FAMILY_NAME="Nightjar"
FAMILY_TAG='NJCFG3|c2='
FAMILY_GLOB='nightjar-*'      # how a corpus file's ground truth is read

# ---------------------------------------------------------------------------
# The pass marks status.sh prints and selftest.sh asserts.
#
# The corpus floor is every family build and no false positive, because the
# corpus is what the learner can see and a rule that cannot separate files in
# front of it has nothing to generalise. The holdout floor is the same, and it
# is the one that is hard: three single-feature rules reach it on the corpus and
# each of them has exactly one false positive here.
CORPUS_TP_REQUIRED=8
CORPUS_FP_ALLOWED=0
HOLDOUT_TP_REQUIRED=3
HOLDOUT_FP_ALLOWED=0

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# otherwise only rebuilt when it is missing, which means an edit to
# image/Dockerfile or to a sample source never reaches a machine that built the
# image once: the container keeps running the previous corpus and the handout
# describes samples the learner does not have.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

build_target() {   # <image> <target>
    docker build --target "$2" -t "$1" "$LAB_DIR/image" \
        || { echo "failed to build $1 (--target $2)" >&2; return 1; }
}

ensure_images() {
    local img target
    for pair in "$HOST_IMAGE:analysis" "$HOLDOUT_IMAGE:holdout"; do
        img="${pair%%:*}"; target="${pair##*:}"
        if ! docker image inspect "$img" >/dev/null 2>&1; then
            echo "[spawn] building $img from $LAB_DIR/image --target $target (first run only)"
            build_target "$img" "$target" || return 1
        elif image_older_than_source "$img" "$LAB_DIR/image"; then
            echo "[spawn] rebuilding $img: $LAB_DIR/image changed since it was built"
            build_target "$img" "$target" || return 1
        fi
    done
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

# --- the learner's rule file -----------------------------------------------

# Has the learner written a rule file at all?
rules_present() {
    docker exec "$WORKSTATION_CTN" test -s "$RULES_FILE" 2>/dev/null
}

# Does it compile? yara exits 1 on a rule file it cannot parse, and prints the
# reason on standard error. The reason is what the caller wants, so it is
# returned rather than discarded.
rules_error() {
    docker exec "$WORKSTATION_CTN" sh -c \
        "yara '$RULES_FILE' /dev/null 2>&1 >/dev/null" 2>/dev/null
}

rules_compile() {
    docker exec "$WORKSTATION_CTN" sh -c \
        "yara '$RULES_FILE' /dev/null >/dev/null 2>&1"
}

# --- scoring ---------------------------------------------------------------

# Count the .exe files under <dir> inside <container> that the learner's rules
# match, split by whether the file is a family build. The corpus is two
# directories deep (set-a and set-b), so the walk is a find rather than a glob.
#
# One yara invocation per file, deliberately. `yara rules.yar a.exe b.exe`
# parses every argument after the first as a further RULE file, so a multi-file
# invocation fails with a syntax error on the second executable rather than
# scanning it.
#
# Prints: "<true positives> <false positives> <family total> <benign total>"
# followed by one line per false positive, so the caller can name them.
score_dir() {   # <container> <dir> <is_family predicate: glob|truthfile>
    local ctn="$1" dir="$2" mode="$3"
    docker exec "$ctn" sh -c "
        tp=0; fp=0; fam=0; ben=0; fps=''
        for f in \$( find '$dir' -type f -name '*.exe' | sort ); do
            b=\$( basename \"\$f\" )
            isfam=0
            if [ '$mode' = glob ]; then
                case \"\$b\" in $FAMILY_GLOB.exe) isfam=1 ;; esac
            else
                grep -qx \"\$b\" '$HOLDOUT_TRUTH' 2>/dev/null && isfam=1
            fi
            hit=0
            yara /tmp/scoring.yar \"\$f\" 2>/dev/null | grep -q . && hit=1
            if [ \$isfam = 1 ]; then
                fam=\$(( fam + 1 ))
                [ \$hit = 1 ] && tp=\$(( tp + 1 ))
            else
                ben=\$(( ben + 1 ))
                if [ \$hit = 1 ]; then fp=\$(( fp + 1 )); fps=\"\$fps \$b\"; fi
            fi
        done
        echo \"\$tp \$fp \$fam \$ben\"
        for x in \$fps; do echo \"FP \$x\"; done
    " 2>/dev/null
}

# Put the learner's rule file where score_dir expects it, in <container>.
stage_rules() {   # <container>
    local ctn="$1" tmp
    tmp="$( mktemp )"
    docker cp "$WORKSTATION_CTN:$RULES_FILE" "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
    docker cp "$tmp" "$ctn:/tmp/scoring.yar" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
}

# --- Part 4 ----------------------------------------------------------------

# Post one of the client's two files to the scanner and print the reply.
upload() {   # <filename>
    docker exec "$CLIENT_CTN" sh -c \
        "curl -s -m 20 --data-binary @'$UPLOAD_DIR/$1' '$UPLOAD_URL?name=$1'" 2>/dev/null
}

# The verdict word from an upload reply: ACCEPTED, REJECTED, SCANNER, or empty.
verdict_of() {   # reads the reply on stdin
    grep -oE '^(ACCEPTED|REJECTED|SCANNER ERROR)' | head -1
}

deployed_present() {
    docker exec "$SCANNER_CTN" test -s "$DEPLOYED_DB" 2>/dev/null
}
