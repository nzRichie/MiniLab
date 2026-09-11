#!/bin/sh
# Starter config for web: the storefront, and the machine both vulnerable
# endpoints run on.
#
# Nothing on this host is a graded defence. The learner never edits either PHP
# file and never changes anything here: the whole of Part 2 is worked on the
# database. This script exists so that a spawn and a reset both leave the two
# endpoints byte-identical to the copies baked into the image, which is what
# lets the handout quote a line of source and be right about it.
#
# The database credentials go outside the document root, at /etc/minilabs, which
# is correct practice and is why no technique in this lab recovers them by
# fetching a URL.
set -eu

PREFIXLEN=24
WEB_IP="122.0.0.10"
DB_IP="122.0.0.20"
LAN_IF="122-lan"

WEBROOT="/var/www/html"
SEARCH_PRISTINE="/usr/local/lib/minilabs/search.php"
STOCK_PRISTINE="/usr/local/lib/minilabs/stock.php"
DB_INC="/etc/minilabs/db.inc.php"
LIGHTTPD_CONF="/etc/lighttpd/shop.conf"
LIGHTTPD_PID="/run/lighttpd.pid"
PHP_CGI="/usr/bin/php-cgi82"

DB_NAME="shop"
APP_USER="appuser"
APP_PASS="sh0p-app-2019"

ip addr replace "${WEB_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# ---------------------------------------------------------------------------
# Stop the server before rewriting anything underneath it. pkill -x matches the
# process NAME exactly, so it cannot match this script; PID 1 in this container
# is `sleep infinity` and nothing here may match it.
pkill -x lighttpd 2>/dev/null || true
rm -f "$LIGHTTPD_PID"

# ---------------------------------------------------------------------------
# The application. Both endpoints are reinstalled from the pristine copies, and
# anything else a previous run left in the document root goes, so a reset cannot
# leave a third page behind. Every mode is set explicitly rather than left to the
# ambient umask, which docker exec sets to 0022 under a rootful daemon and 0000
# under a rootless one.
rm -rf "$WEBROOT"
mkdir -p "$WEBROOT"
cp "$SEARCH_PRISTINE" "${WEBROOT}/search.php"
cp "$STOCK_PRISTINE"  "${WEBROOT}/stock.php"

cat > "${WEBROOT}/index.html" <<'HTML'
<!doctype html>
<title>Harkness Tools</title>
<h1>Harkness Tools</h1>
<p>Search the catalogue: <a href="/search.php?q=harkness">/search.php?q=harkness</a></p>
<p>Check stock for a product: <a href="/stock.php?sku=3">/stock.php?sku=3</a></p>
HTML

chown -R root:root "$WEBROOT"
chmod 755 "$WEBROOT"
chmod 644 "${WEBROOT}/search.php" "${WEBROOT}/stock.php" "${WEBROOT}/index.html"

# ---------------------------------------------------------------------------
# The credentials the endpoints connect with. mysqli in PHP 8.1 and later reports
# an error by throwing mysqli_sql_exception rather than by returning false; both
# endpoints catch it, so this file does not change that behaviour and the pages
# print their own fixed text rather than the server's error message.
mkdir -p "$(dirname "$DB_INC")"
chmod 755 "$(dirname "$DB_INC")"
cat > "$DB_INC" <<CONF
<?php
// Database credentials for the storefront. Outside the document root, so no
// request can fetch this file.
define("DB_HOST", "${DB_IP}");
define("DB_USER", "${APP_USER}");
define("DB_PASS", "${APP_PASS}");
define("DB_NAME", "${DB_NAME}");
CONF
chmod 644 "$DB_INC"

# ---------------------------------------------------------------------------
# The server. mod_cgi hands any .php file to php-cgi; static-file.exclude-extensions
# keeps the same file from being served as text when mod_cgi is not reached.
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

echo "web: addressed ${WEB_IP}, lighttpd serving ${WEBROOT}/search.php and ${WEBROOT}/stock.php against ${DB_IP}"
