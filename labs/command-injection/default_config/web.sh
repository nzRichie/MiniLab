#!/bin/sh
# Starter config for web: the appliance, and the machine Parts 2A and 2B are
# worked on.
#
# It arrives serving the public network-tools page over lighttpd, with two
# deployment mistakes that Parts 2A and 2B correct. Neither of them is the
# vulnerability: the vulnerability is in the program, and the program does not
# change. Both mistakes decide what the vulnerability is worth.
#
#   no server.username   lighttpd is started as root and given no account to
#                        change to, so it stays root and every CGI it runs is
#                        root. Part 2A sets the two directives that fix this.
#   webroot owned by svc a deploy script chowned /var/www to the service account
#                        so that a release could be unpacked in place. Once Part
#                        2A has the CGI running as svc, that ownership is what
#                        lets an injected command write a second CGI next to the
#                        first. Part 2B takes it back.
#
# It is idempotent: reset.sh re-runs it, and it reinstalls the CGI from the
# pristine copy in the image and rewrites the configuration from scratch, so a
# learner who edited or deleted either gets the original back.
set -eu

PREFIXLEN=24
WEB_IP="120.0.0.10"
GW_INSIDE_IP="120.0.0.1"
LAN_IF="120-lan"

WEBROOT="/var/www"
CGI_DIR="${WEBROOT}/cgi-bin"
CGI_FILE="${CGI_DIR}/diag.cgi"
CGI_PRISTINE="/usr/local/lib/minilabs/diag.cgi"
LIGHTTPD_CONF="/etc/lighttpd/appliance.conf"
LIGHTTPD_PID="/run/lighttpd.pid"

MARKER_FILE="/etc/appliance/backup.key"
MARKER_STRING="APPLIANCE-BACKUP-KEY-9F2C41D7B0A38E56"

ip addr replace "${WEB_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up
ip route replace default via "$GW_INSIDE_IP"

# ---------------------------------------------------------------------------
# Stop whatever is running before rewriting anything underneath it. pkill -x
# matches the process NAME exactly rather than the whole argv, so it cannot
# match this script; PID 1 in this container is `sleep infinity` and nothing
# here may match it.
pkill -x lighttpd 2>/dev/null || true
rm -f "$LIGHTTPD_PID"

# ---------------------------------------------------------------------------
# The appliance's own key. Mode 0600 root:root: readable by the CGI while the
# CGI is root, and not afterwards. Every mode below is set explicitly rather
# than left to the ambient umask, which docker exec sets to 0022 under a rootful
# daemon and 0000 under a rootless one.
mkdir -p /etc/appliance
chmod 755 /etc/appliance
printf '%s\n' "$MARKER_STRING" > "$MARKER_FILE"
chown root:root "$MARKER_FILE"
chmod 600 "$MARKER_FILE"

# ---------------------------------------------------------------------------
# The web content. Any file a previous run or a previous attacker left in the
# CGI directory goes, so a reset cannot leave a webshell behind.
rm -rf "$CGI_DIR"
mkdir -p "$WEBROOT/html" "$CGI_DIR"

cat > "$WEBROOT/html/index.html" <<'HTML'
<!doctype html>
<title>appliance</title>
<h1>appliance</h1>
<p>Network tools: <a href="/cgi-bin/diag.cgi?host=127.0.0.1">reachability check</a></p>
HTML

cp "$CGI_PRISTINE" "$CGI_FILE"

# The deployment mistake Part 2B corrects: the release account owns the tree and
# the group may write into it.
chown -R svc:svc "$WEBROOT"
chmod 775 "$WEBROOT" "$WEBROOT/html" "$CGI_DIR"
chmod 775 "$CGI_FILE"
chmod 664 "$WEBROOT/html/index.html"

# ---------------------------------------------------------------------------
# The server. mod_alias maps the /cgi-bin/ prefix onto the directory, and
# mod_cgi with an empty interpreter executes the file itself rather than handing
# it to one, which is what makes both the compiled diag.cgi and any shell script
# an attacker leaves beside it runnable.
#
# server.username and server.groupname are absent on purpose. lighttpd started
# as root with no account named to change to keeps running as root, so every CGI
# it starts is root. Part 2A adds the two lines.
# The error log and its directory belong to the service account from the start,
# not because Part 2A needs them to but because a packaged web server's log
# directory belongs to the account the package runs as. lighttpd opens its error
# log AFTER it changes to the account named by server.username, so a log file
# only root could append to would make Part 2A fail to start the server for a
# reason that has nothing to do with the stage. The file is created here rather
# than left to lighttpd, because a file lighttpd creates while it is still root
# is root's.
rm -f /var/log/lighttpd/error.log
mkdir -p /var/log/lighttpd
: > /var/log/lighttpd/error.log
chown -R svc:svc /var/log/lighttpd
chmod 755 /var/log/lighttpd
chmod 644 /var/log/lighttpd/error.log
cat > "$LIGHTTPD_CONF" <<CONF
server.document-root = "${WEBROOT}/html"
server.port          = 80
server.pid-file      = "${LIGHTTPD_PID}"
server.errorlog      = "/var/log/lighttpd/error.log"
server.modules       = ( "mod_alias", "mod_cgi" )

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

echo "web: addressed ${WEB_IP}, lighttpd serving ${CGI_FILE} as root, ${WEBROOT} owned by svc"
