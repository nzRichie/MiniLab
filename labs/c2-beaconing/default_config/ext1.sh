#!/bin/sh
# Starter config for ext1: one of the two hosts standing in for the internet.
#
# It carries two of the five outside addresses, and both of them are legitimate:
# the package mirror every workstation fetches from, and a documentation site.
# Which container an outside address sits on says nothing about what that
# address is, which is why ext2 holds one legitimate service beside the
# controller.
#
# Nothing here is the exercise. What this establishes is the traffic the implant
# has to be told apart from: several destinations, uneven request rates, and
# replies of very different sizes.
#
# It is idempotent. reset.sh re-runs it, and selftest.sh re-runs it between
# stages, so there is one definition of how this machine is set up rather than
# three.
set -eu

PREFIXLEN=24
MIRROR_IP="118.1.0.10"
DOCS_IP="118.1.0.30"
GW_OUTSIDE_IP="118.1.0.1"
EXT_IF="118-ext"

WEB_ROOT="/var/www/localhost/htdocs"
LIGHTTPD_PID="/run/lighttpd.pid"

ip addr replace "${MIRROR_IP}/${PREFIXLEN}" dev "$EXT_IF"
ip addr replace "${DOCS_IP}/${PREFIXLEN}" dev "$EXT_IF"
ip link set "$EXT_IF" up

# The outside hosts need a route back to the inside segment, and the gateway is
# the only way there. It is a default route rather than a route to 118.0.0.0/24
# because a host on the internet does not hold a route to each network that
# reaches it, and because a reply that could not find its way back would look to
# the learner like a filter rather than like a missing route.
ip route replace default via "$GW_OUTSIDE_IP"

# ---------------------------------------------------------------------------
# The two sites. One lighttpd bound to every address on this machine serves
# both, because the pages are what the workstations fetch and which of the two
# addresses served a page changes nothing about the flow a capture records.
#
# The four pages differ in size by two orders of magnitude, which is the whole
# reason they exist: a destination whose replies are all within a few bytes of
# each other is a signal, and it is only a signal if the other destinations'
# replies are not.
mkdir -p "$WEB_ROOT"
chmod 755 "$WEB_ROOT"

cat > "${WEB_ROOT}/index.html" <<'EOF'
<html><body><h1>package mirror</h1><p>index of /</p></body></html>
EOF

# Three files of roughly 2 KB, 9 KB and 30 KB. `yes | head -c` gives an exact
# size without needing a file of known length to copy from.
{ echo "<html><body><h1>release notes</h1><pre>"; yes "release note line" | head -c 2000; echo "</pre></body></html>"; } > "${WEB_ROOT}/notes.html"
{ echo "<html><body><h1>package guide</h1><pre>"; yes "guide paragraph text" | head -c 9000; echo "</pre></body></html>"; } > "${WEB_ROOT}/guide.html"
{ echo "<html><body><h1>changelog</h1><pre>"; yes "changelog entry line" | head -c 30000; echo "</pre></body></html>"; } > "${WEB_ROOT}/changelog.html"

chmod 644 "${WEB_ROOT}"/*.html

# ---------------------------------------------------------------------------
# Stopping a daemon means waiting for it to let go of its port.
#
# `kill` returns as soon as the signal is queued, not when the process has
# exited. Starting the replacement immediately then races the old process's exit,
# and the loser fails to bind with "Address in use" and exits, leaving the
# PREVIOUS daemon listening with the content this script was run to replace. A
# reset that hits that race reports itself done and changes nothing.
stop_and_wait() {   # <pid file> <process name> <port it must release>
    if [ -f "$1" ]; then
        kill "$( cat "$1" )" 2>/dev/null || true
    fi
    pkill -x "$2" 2>/dev/null || true
    i=0
    while [ "$i" -lt 50 ]; do
        netstat -tln 2>/dev/null | grep -q ":$3 " || return 0
        i=$(( i + 1 ))
        sleep 0.1
    done
    if [ -f "$1" ]; then kill -9 "$( cat "$1" )" 2>/dev/null || true; fi
    pkill -9 -x "$2" 2>/dev/null || true
    sleep 0.5
}

# lighttpd drops privileges to server.username and only then opens its logs, so
# an access log this script created as root leaves mod_accesslog with
# "Permission denied" and takes the whole instance down. Removing the file lets
# lighttpd create it as the account that will write to it.
stop_and_wait "$LIGHTTPD_PID" lighttpd 80
rm -f /var/log/lighttpd/access.log
lighttpd -f /etc/lighttpd/lighttpd.conf

echo "ext1: addressed ${MIRROR_IP} and ${DOCS_IP}, serving four pages on tcp/80"
