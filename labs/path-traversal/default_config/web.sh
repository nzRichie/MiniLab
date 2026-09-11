#!/bin/sh
# Starter config for web: the portal, and the only host the traversal reads any
# file on.
#
# Two of Part 2's four stages are worked here, and both are configuration:
# stage 2A adds a rule to the web server's own configuration file, and stage 2B
# sets one directive in PHP's. Neither touches view.php, which is where the bug
# is and where it stays.
#
# This script is what makes a reset mean something on this host. It reinstalls
# view.php and the documents from the pristine copies, rewrites the web server's
# configuration without the rule, and puts the packaged php.ini back without the
# directive, so a spawn and a reset both leave the machine in the same state.
set -eu

PREFIXLEN=24
WEB_IP="123.0.0.10"
DB_IP="123.0.0.20"
LAN_IF="123-lan"

WEBROOT="/var/www/html"
DOC_DIR="/srv/docs"
VIEW_PRISTINE="/usr/local/lib/minilabs/view.php"
DOCS_PRISTINE="/usr/local/lib/minilabs/docs"
PHPINI_PRISTINE="/usr/local/lib/minilabs/php.ini"
PHP_INI="/etc/php82/php.ini"
DB_INC="/etc/minilabs/db.inc.php"
LIGHTTPD_CONF="/etc/lighttpd/portal.conf"
LIGHTTPD_PID="/run/lighttpd.pid"
PHP_CGI="/usr/bin/php-cgi82"

DB_NAME="portal"
APP_USER="portalapp"
APP_PASS="Br1ndle-portal-2019"

ip addr replace "${WEB_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# ---------------------------------------------------------------------------
# Stop the server before rewriting anything underneath it. pkill -x matches the
# process NAME exactly, so it cannot match this script; PID 1 in this container
# is `sleep infinity` and nothing here may match it.
pkill -x lighttpd 2>/dev/null || true
rm -f "$LIGHTTPD_PID"

# ---------------------------------------------------------------------------
# The application. view.php is reinstalled from the pristine copy and anything
# else a previous run left in the document root goes, so a reset cannot leave a
# second page behind. Every mode is set explicitly rather than left to the
# ambient umask, which docker exec sets to 0022 under a rootful daemon and 0000
# under a rootless one.
rm -rf "$WEBROOT"
mkdir -p "$WEBROOT"
cp "$VIEW_PRISTINE" "${WEBROOT}/view.php"

cat > "${WEBROOT}/index.html" <<'HTML'
<!doctype html>
<title>Brindle Logistics -- customer portal</title>
<h1>Brindle Logistics</h1>
<p>Customer documents:</p>
<ul>
  <li><a href="/view.php?file=returns-policy.txt">Returns and claims policy</a></li>
  <li><a href="/view.php?file=tariff-2026.txt">Standard tariff, 2026</a></li>
  <li><a href="/view.php?file=depot-hours.txt">Depot collection hours</a></li>
</ul>
HTML

chown -R root:root "$WEBROOT"
chmod 755 "$WEBROOT"
chmod 644 "${WEBROOT}/view.php" "${WEBROOT}/index.html"

# ---------------------------------------------------------------------------
# The documents the viewer serves. They sit OUTSIDE the document root, so a
# request cannot fetch one by its own URL and the viewer is the only way to read
# one. That placement is what the viewer exists for, and it is also why the
# traversal reaches the whole filesystem rather than the document root alone.
rm -rf "$DOC_DIR"
mkdir -p "$DOC_DIR"
cp "$DOCS_PRISTINE"/*.txt "$DOC_DIR"/
chown -R root:root "$DOC_DIR"
chmod 755 "$DOC_DIR"
chmod 644 "$DOC_DIR"/*.txt

# ---------------------------------------------------------------------------
# The credentials the viewer includes. They sit outside the document root too,
# for the same reason and with the same limit: no request FETCHES this file, and
# the traversal READS it.
#
# mysqli in PHP 8.1 and later reports an error by throwing mysqli_sql_exception
# rather than by returning false; view.php catches it, so this file does not
# change that behaviour and the page prints its own fixed text rather than the
# server's error message.
mkdir -p "$(dirname "$DB_INC")"
chmod 755 "$(dirname "$DB_INC")"
cat > "$DB_INC" <<CONF
<?php
// Database credentials for the customer portal. Outside the document root, so
// no request can fetch this file.
define("DB_HOST", "${DB_IP}");
define("DB_USER", "${APP_USER}");
define("DB_PASS", "${APP_PASS}");
define("DB_NAME", "${DB_NAME}");
CONF
chmod 644 "$DB_INC"

# ---------------------------------------------------------------------------
# PHP's own configuration, put back exactly as the package shipped it. The
# pristine copy was taken at image build time, so this cannot drift against the
# packaged file, and it is what removes stage 2B's open_basedir on a reset.
cp "$PHPINI_PRISTINE" "$PHP_INI"
chmod 644 "$PHP_INI"

# ---------------------------------------------------------------------------
# The web server. mod_cgi hands any .php file to php-cgi;
# static-file.exclude-extensions keeps the same file from being served as text
# when mod_cgi is not reached.
#
# server.modules names mod_cgi and nothing else. Stage 2A is where the learner
# adds mod_access and the condition that uses it; leaving it out here is what
# makes that stage a change the learner writes rather than one they enable.
rm -f /var/log/lighttpd/error.log
mkdir -p /var/log/lighttpd
: > /var/log/lighttpd/error.log
chmod 755 /var/log/lighttpd
chmod 644 /var/log/lighttpd/error.log

cat > "$LIGHTTPD_CONF" <<CONF
server.document-root = "${WEBROOT}"
server.port          = 80
server.pid-file      = "${LIGHTTPD_PID}"
server.errorlog      = "/var/log/lighttpd/error.log"
server.modules       = ( "mod_cgi" )

index-file.names = ( "index.html" )
mimetype.assign  = ( ".html" => "text/html", ".txt" => "text/plain" )

static-file.exclude-extensions = ( ".php" )
cgi.assign = ( ".php" => "${PHP_CGI}" )
CONF
chmod 644 "$LIGHTTPD_CONF"

lighttpd -f "$LIGHTTPD_CONF"

echo "web: addressed ${WEB_IP}, lighttpd serving ${WEBROOT}/view.php over documents in ${DOC_DIR}, database at ${DB_IP}"
