#!/bin/sh
# Starter config for reports: the nightly report job, and the second tier that
# connects to the portal's database.
#
# Nothing on this host is a graded defence and nothing here is vulnerable. The
# host exists to make one fact observable: the account the traversal discloses
# on the web tier is in use from a second address, so binding that account to
# the web tier's address stops this job. That is stage 2C's wrong answer, and a
# lab without this host could not show it.
#
# Stage 2D is the point at which this host's credential file changes, and the
# learner edits it themselves. This script rewrites it with the shared account,
# so a reset puts both tiers back on one credential.
set -eu

PREFIXLEN=24
REPORTS_IP="123.0.0.30"
DB_IP="123.0.0.20"
LAN_IF="123-lan"

REPORT_CNF="/etc/minilabs/report.cnf"
APP_USER="portalapp"
APP_PASS="Br1ndle-portal-2019"

ip addr replace "${REPORTS_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# ---------------------------------------------------------------------------
# The job's credentials, in the defaults file the mariadb client reads them from
# with --defaults-extra-file. Mode 0600: this file is not what any technique in
# this lab reads, and leaving it world-readable would suggest it was.
#
# It holds the same account and the same password as the web tier's
# /etc/minilabs/db.inc.php, and that is the deployment the lab is about. The
# traversal never reaches this host, so what makes this file's contents an
# attacker's problem is not where it is: it is that the same credential is on
# the machine the traversal does reach.
mkdir -p "$(dirname "$REPORT_CNF")"
chmod 755 "$(dirname "$REPORT_CNF")"
cat > "$REPORT_CNF" <<CONF
[client]
host=${DB_IP}
user=${APP_USER}
password=${APP_PASS}
CONF
chown root:root "$REPORT_CNF"
chmod 600 "$REPORT_CNF"

echo "reports: addressed ${REPORTS_IP}, nightly-report runs as ${APP_USER} against ${DB_IP}"
