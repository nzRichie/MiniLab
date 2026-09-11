#!/bin/sh
# Starter config for db: MariaDB, and the machine stages 2C and 2D are worked on.
#
# It arrives serving the portal's database with one deployment mistake, and the
# mistake is not a privilege:
#
#   'portalapp'@'%'   one account, shared by the portal and by the nightly
#                     report job, and accepted from any address. Stage 2C
#                     narrows that host part to the web tier, which refuses the
#                     attacker and stops the report job at the same time. Stage
#                     2D splits it into one account per tier, each bound to its
#                     own tier's address, which is the state that holds all
#                     three facts at once.
#
# Its SELECT grant covers the whole database rather than the one table the
# portal reads, so the account reaches the customer table as well. That is a
# second mistake and this lab does not grade it: narrowing a grant is what the
# SQL injection lab is built around, and the control this lab is built around is
# WHERE an account may be used from rather than WHAT it may read. The answer key
# says so.
#
# It is idempotent: reset.sh re-runs it, and it reloads the schema and rewrites
# every account from scratch, so a learner who renamed an account, created two,
# or dropped the shared one gets the original back.
set -eu

PREFIXLEN=24
DB_IP="123.0.0.20"
LAN_IF="123-lan"

DB_NAME="portal"
APP_USER="portalapp"
APP_PASS="Br1ndle-portal-2019"
WEB_USER="portalweb"
REPORT_USER="portalreports"
WEB_IP="123.0.0.10"
REPORTS_IP="123.0.0.30"
SCHEMA_PRISTINE="/usr/local/lib/minilabs/schema.sql"

ip addr replace "${DB_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# ---------------------------------------------------------------------------
# The server's own configuration. The file is named zz-lab.cnf because
# /etc/my.cnf includes /etc/my.cnf.d in glob order and the packaged
# mariadb-server.cnf sets `skip-networking`; a file that sorts before it is read
# first and then overridden, which leaves the server listening on nothing at all.
#
# skip-name-resolve=1 is load-bearing for the whole of Part 2. With it set, the
# host part of an account is matched against the client's address; without it,
# the server resolves that address to a name first and matches the name, and
# these containers have no reverse zone to resolve in.
mkdir -p /run/mysqld /etc/my.cnf.d
chown mysql:mysql /run/mysqld
chmod 755 /run/mysqld
cat > /etc/my.cnf.d/zz-lab.cnf <<CONF
[mysqld]
skip-networking=0
bind-address=0.0.0.0
port=3306
skip-name-resolve=1
CONF
chmod 644 /etc/my.cnf.d/zz-lab.cnf

# ---------------------------------------------------------------------------
# Initialise the data directory on the first run only, then start the server.
# mariadb-install-db writes the system tables; running it against a directory
# that already has them leaves them alone, but skipping it keeps a reset fast.
if [ ! -d /var/lib/mysql/mysql ]; then
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null 2>&1
fi

# pkill -x matches the process NAME exactly rather than the whole argv, so it
# cannot match this script. PID 1 in this container is `sleep infinity` and
# nothing here may match it.
pkill -x mariadbd 2>/dev/null || true
i=0
while pgrep -x mariadbd >/dev/null 2>&1 && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i+1)); done

setsid mariadbd --user=mysql >/var/log/mariadbd.log 2>&1 &

i=0
while [ "$i" -lt 120 ]; do
    if mariadb -u root -e "SELECT 1" >/dev/null 2>&1; then break; fi
    sleep 0.5
    i=$((i+1))
done
mariadb -u root -e "SELECT 1" >/dev/null 2>&1 || {
    echo "db: mariadbd did not accept a connection; see /var/log/mariadbd.log" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# The data. schema.sql drops and recreates the database, so a reset undoes
# anything a learner or an attacker changed in it.
mariadb -u root < "$SCHEMA_PRISTINE"

# ---------------------------------------------------------------------------
# The accounts. Every account either stage of Part 2 could have created is
# dropped first, so a reset reaches the starter state from wherever the learner
# left it: from the shared account renamed to one address, from a pair of
# per-tier accounts, or from both at once.
mariadb -u root <<SQL
DROP USER IF EXISTS '${APP_USER}'@'%';
DROP USER IF EXISTS '${APP_USER}'@'${WEB_IP}';
DROP USER IF EXISTS '${APP_USER}'@'${REPORTS_IP}';
DROP USER IF EXISTS '${WEB_USER}'@'${WEB_IP}';
DROP USER IF EXISTS '${WEB_USER}'@'%';
DROP USER IF EXISTS '${REPORT_USER}'@'${REPORTS_IP}';
DROP USER IF EXISTS '${REPORT_USER}'@'%';
CREATE USER '${APP_USER}'@'%' IDENTIFIED BY '${APP_PASS}';
GRANT SELECT ON ${DB_NAME}.* TO '${APP_USER}'@'%';
FLUSH PRIVILEGES;
SQL

echo "db: addressed ${DB_IP}, MariaDB on 3306, one account ${APP_USER}@% shared by both tiers with SELECT on ${DB_NAME}.*"
