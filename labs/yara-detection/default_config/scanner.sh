#!/bin/sh
# Starter config for scanner: the upload endpoint Part 4 deploys to.
#
# It arrives serving /cgi-bin/upload.cgi over lighttpd with NO database at
# /etc/minilabs/deployed.yar, so every upload comes back "SCANNER ERROR: no
# database" until the learner puts one there. That absence is the starting
# state of Part 4: the endpoint is running and it enforces nothing.
#
# The CGI is reinstalled from the pristine copy in the image on every spawn and
# every reset, so a learner who edited it gets the original back. The database
# is removed for the same reason: a database from an earlier attempt would make
# the first upload of the next attempt lie about what the learner deployed.
set -eu

PREFIXLEN=24
SCANNER_IP="126.0.0.20"
LAN_IF="126-lan"

DEPLOYED_DB="/etc/minilabs/deployed.yar"
CGI_PRISTINE="/usr/local/lib/minilabs/upload.cgi"
WEBROOT="/var/www"
CGI_DIR="${WEBROOT}/cgi-bin"
CGI_FILE="${CGI_DIR}/upload.cgi"
LIGHTTPD_CONF="/etc/lighttpd/scanner.conf"
LIGHTTPD_PID="/run/lighttpd.pid"

ip addr replace "${SCANNER_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# Stop whatever is running before rewriting anything underneath it. pkill -x
# matches the process NAME exactly rather than the whole argv, so it cannot
# match this script; PID 1 in this container is `sleep infinity` and nothing
# here may match it.
pkill -x lighttpd 2>/dev/null || true
rm -f "$LIGHTTPD_PID"

# No database. Part 4 is what puts one here.
rm -f "$DEPLOYED_DB"
mkdir -p /etc/minilabs
chmod 755 /etc/minilabs

# Where the CGI writes an upload while it scans it. Each upload is removed as
# soon as its verdict is printed, so nothing accumulates and no sample is left
# on a machine the handout does not describe.
rm -rf /var/spool/uploads
mkdir -p /var/spool/uploads
chmod 755 /var/spool/uploads

# The web content. Every mode is set explicitly rather than left to the ambient
# umask, which docker exec sets to 0022 under a rootful daemon and 0000 under a
# rootless one.
rm -rf "$CGI_DIR"
mkdir -p "${WEBROOT}/html" "$CGI_DIR"
cat > "${WEBROOT}/html/index.html" <<'HTML'
<!doctype html>
<title>upload scanner</title>
<h1>upload scanner</h1>
<p>POST a file body to <code>/cgi-bin/upload.cgi?name=FILENAME</code>.</p>
HTML
cp "$CGI_PRISTINE" "$CGI_FILE"
chmod 755 "$WEBROOT" "${WEBROOT}/html" "$CGI_DIR" "$CGI_FILE"
chmod 644 "${WEBROOT}/html/index.html"

# lighttpd opens its error log before it serves anything and refuses to start if
# the directory is missing. It runs as root here and stays root: nothing in this
# lab turns on privilege separation, because what is being taught is the rule
# file and not the web server.
mkdir -p /var/log/lighttpd
: > /var/log/lighttpd/error.log
chmod 755 /var/log/lighttpd
chmod 644 /var/log/lighttpd/error.log

# mod_alias maps the /cgi-bin/ prefix onto the directory and mod_cgi with an
# empty interpreter executes the file itself. server.max-request-size is set
# rather than left alone: lighttpd 1.4's default for it is 0, meaning no limit,
# and an upload endpoint that will buffer a request of any size is not a thing
# to ship. 8192 kbytes is more than thirty times the larger of the two files the
# client sends (logtag-check.exe, 240 kbytes), so nothing in the lab is ever
# refused for its size.
cat > "$LIGHTTPD_CONF" <<CONF
server.document-root   = "${WEBROOT}/html"
server.port            = 80
server.pid-file        = "${LIGHTTPD_PID}"
server.errorlog        = "/var/log/lighttpd/error.log"
server.modules         = ( "mod_alias", "mod_cgi" )
server.max-request-size = 8192

index-file.names = ( "index.html" )
mimetype.assign  = ( ".html" => "text/html", ".txt" => "text/plain" )

static-file.exclude-extensions = ( ".cgi" )
alias.url += ( "/cgi-bin/" => "${CGI_DIR}/" )

\$HTTP["url"] =~ "^/cgi-bin/" {
    cgi.assign = ( "" => "" )
}
CONF
chmod 644 "$LIGHTTPD_CONF"

lighttpd -f "$LIGHTTPD_CONF"

echo "scanner: addressed ${SCANNER_IP}, upload endpoint serving, no database at ${DEPLOYED_DB}"
