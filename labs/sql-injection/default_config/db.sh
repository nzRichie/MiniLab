#!/bin/sh
# Starter config for db: MariaDB, and the machine every stage of Part 2 is
# worked on.
#
# It arrives serving the storefront's database over the network with three
# deployment mistakes that Part 2 corrects. None of them is the vulnerability:
# the vulnerability is in the two PHP endpoints, and neither program changes.
# All three decide what the vulnerability is worth.
#
#   SELECT on shop.*   the application reads one table and was granted the whole
#                      database. Part 2A narrows it, which ends the UNION and the
#                      blind extraction at once.
#   FILE on *.*        a web application has no use for reading files off the
#                      database host. Part 2B revokes it. It survives Part 2A on
#                      purpose: FILE is a global privilege and 2A's revoke is
#                      scoped to shop.*.
#   no source filter   any host on the segment may open a connection to 3306.
#                      Part 2C is where the learner writes the rule that ends
#                      that, and it is the only stage that stops an attacker who
#                      already holds a password.
#
# It is idempotent: reset.sh re-runs it, and it reloads the schema and rewrites
# every account from scratch, so a learner who dropped a table or changed a grant
# gets the original back.
set -eu

PREFIXLEN=24
DB_IP="122.0.0.20"
LAN_IF="122-lan"

DB_NAME="shop"
APP_USER="appuser"
APP_PASS="sh0p-app-2019"
BACKUP_USER="backup"
BACKUP_PASS="Bk9-QW3rf-2019"
BACKUP_CNF="/etc/mysql/backup.cnf"
SCHEMA_PRISTINE="/usr/local/lib/minilabs/schema.sql"
NFT_TABLE="dbguard"

ip addr replace "${DB_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# ---------------------------------------------------------------------------
# Remove the table Part 2C creates, so a reset returns the database to accepting
# a connection from every host on the segment.
nft delete table inet "$NFT_TABLE" 2>/dev/null || true

# ---------------------------------------------------------------------------
# The server's own configuration. The file is named zz-lab.cnf because /etc/my.cnf
# includes /etc/my.cnf.d in glob order and the packaged mariadb-server.cnf sets
# `skip-networking`; a file that sorts before it is read first and then overridden,
# which leaves the server listening on nothing at all.
#
# secure_file_priv is left at its default. In MariaDB that default places no
# restriction on which directories LOAD_FILE may read from, which is not the same
# as MySQL, where an unset value disables the function outright. Nothing here
# weakens it: technique 1D works against a MariaDB 10.11 that was never
# reconfigured, and revoking FILE is what stops it.
mkdir -p /run/mysqld /etc/my.cnf.d /etc/mysql
chown mysql:mysql /run/mysqld
chmod 755 /run/mysqld /etc/mysql
cat > /etc/my.cnf.d/zz-lab.cnf <<CONF
[mysqld]
skip-networking=0
bind-address=0.0.0.0
port=3306
skip-name-resolve=1
CONF
chmod 644 /etc/my.cnf.d/zz-lab.cnf

# ---------------------------------------------------------------------------
# The nightly dump job's credentials, on disk on this host. Mode 0644 because
# LOAD_FILE returns the contents of a file only when it is readable by all, and
# a config file left world-readable is the ordinary way a password ends up
# reachable that way. Nothing in Part 2 changes this file: tightening it would
# close technique 1D too, and the stage that closes 1D is the FILE revoke.
cat > "$BACKUP_CNF" <<CONF
# Credentials used by the nightly dump job on the backup host.
# Read by mariadb-dump --defaults-extra-file=/etc/mysql/backup.cnf
[client]
user=${BACKUP_USER}
password=${BACKUP_PASS}
CONF
chown root:root "$BACKUP_CNF"
chmod 644 "$BACKUP_CNF"

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
# The accounts. Both are dropped and recreated rather than altered, so a reset
# reaches the starter grants whatever the learner revoked or granted.
#
# The two GRANT statements for appuser cannot be combined: FILE is a global
# privilege and MariaDB accepts it only with ON *.*, while SELECT is being given
# at database scope. That split is what makes Part 2B a separate stage from
# Part 2A rather than a consequence of it.
mariadb -u root <<SQL
DROP USER IF EXISTS '${APP_USER}'@'%';
DROP USER IF EXISTS '${BACKUP_USER}'@'%';
CREATE USER '${APP_USER}'@'%' IDENTIFIED BY '${APP_PASS}';
GRANT SELECT ON ${DB_NAME}.* TO '${APP_USER}'@'%';
GRANT FILE ON *.* TO '${APP_USER}'@'%';
CREATE USER '${BACKUP_USER}'@'%' IDENTIFIED BY '${BACKUP_PASS}';
GRANT SELECT, LOCK TABLES ON ${DB_NAME}.* TO '${BACKUP_USER}'@'%';
FLUSH PRIVILEGES;
SQL

echo "db: addressed ${DB_IP}, MariaDB on 3306 open to the whole segment, ${APP_USER} holds SELECT on ${DB_NAME}.* and FILE on *.*"
