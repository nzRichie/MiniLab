#!/bin/sh
# Starter config for the loader: the operator's file host.
#
# It serves one file over plain HTTP: the source text of `flood`, copied out of
# the image's own /usr/local/bin/flood, so the bytes served are the bytes every
# source runs. selftest.sh checks the two are identical.
#
# The tool is already installed on every machine in this lab, so nothing has to
# fetch it to run it. What this host is for is reading it: a learner about to
# send 4500 packets from four machines should be able to see exactly what one of
# those packets is, and `curl http://129.2.0.40/flood` is how.
set -eu

LOADER_IP="129.2.0.40"
PREFIXLEN=24
OP_IF="129-S3"
GW="129.2.0.1"
DOCROOT="/var/www/localhost/htdocs"
ACCESS_LOG="/var/log/lighttpd/access.log"
CONF="/etc/lighttpd/lighttpd.conf"

ip addr replace "${LOADER_IP}/${PREFIXLEN}" dev "$OP_IF"
ip link set "$OP_IF" up
ip route replace default via "$GW"

mkdir -p "$DOCROOT" /var/log/lighttpd
cp /usr/local/bin/flood "$DOCROOT/flood"
chmod 644 "$DOCROOT/flood"

# lighttpd drops privileges to the lighttpd user after binding, so the log
# directory and the file have to belong to that user; a root-owned log gives
# "opening log failed: Permission denied" and lighttpd exits.
: > "$ACCESS_LOG"
chown -R lighttpd:lighttpd /var/log/lighttpd
chmod 644 "$ACCESS_LOG"

if ! grep -q 'mod_accesslog' "$CONF"; then
    printf '\nserver.modules += ( "mod_accesslog" )\naccesslog.filename = "%s"\n' \
        "$ACCESS_LOG" >> "$CONF"
fi

if [ -f /run/lighttpd.pid ]; then kill "$( cat /run/lighttpd.pid )" 2>/dev/null || true; fi
pkill -x lighttpd 2>/dev/null || true
i=0
while [ "$i" -lt 50 ]; do
    netstat -tln 2>/dev/null | grep -q ':80 ' || break
    i=$(( i + 1 )); sleep 0.1
done
lighttpd -f "$CONF"

echo "loader: ${LOADER_IP} serving the flood tool's source at http://${LOADER_IP}/flood"
