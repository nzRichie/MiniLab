#!/bin/sh
# Starter config for web1: one of the two backends behind the proxy.
#
# Both backends are delivered working and stay working until the learner breaks
# one on purpose. Nothing here is the exercise; what this script establishes is
# the two facts every later measurement is read against: the site answers, and
# the health endpoint answers separately from the site.
#
# It is idempotent, and that is load-bearing. reset.sh re-runs it to undo a kill,
# and selftest.sh re-runs it to revive a backend between stages, so there is one
# definition of how a backend is supposed to be set up rather than three.
set -eu

PREFIXLEN=24
WEB_IP="117.1.0.20"
PROXY_BACK_IP="117.1.0.1"
WEB_IF="117-back"

NAME="web1"
WEB_ROOT="/var/www/localhost/htdocs"
HEALTH_FILE="${WEB_ROOT}/health"
LIGHTTPD_PID="/run/lighttpd.pid"
NFT_TABLE="blackhole"

ip addr replace "${WEB_IP}/${PREFIXLEN}" dev "$WEB_IF"
ip link set "$WEB_IF" up
ip route replace default via "$PROXY_BACK_IP"

# Part 4's blackhole is learner-created state on this machine, so it goes here.
# A reset that left the drop rule behind would start the next run with a backend
# already dark and no line in the config to explain it.
nft delete table inet "$NFT_TABLE" 2>/dev/null || true

# ---------------------------------------------------------------------------
# The site. The whole body of the index page is this backend's name, and nothing
# else, because the client tallies which backend answered each request by reading
# the first line of the body. A page with a heading and a paragraph would make
# that tally a parsing exercise instead of a count.
mkdir -p "$WEB_ROOT"
echo "$NAME" > "${WEB_ROOT}/index.html"
chmod 755 "$WEB_ROOT"
chmod 644 "${WEB_ROOT}/index.html"

# The health endpoint, as a separate file from the index page.
#
# That separation is the whole of Part 2. Removing this file leaves lighttpd
# running and the site serving perfectly, and makes GET /health return 404
# instead of 200, so the learner sees a health check remove a backend that has
# not failed in any way a client would notice. A check that could only fail when
# the service was already dead would prove nothing the connection attempt does
# not prove by itself.
#
# It carries no extension, so no mimetype rule matches it and lighttpd serves it
# as application/octet-stream. The check reads the status line, not the body, so
# the content type is irrelevant to it; the body is "OK" so that a learner who
# curls the endpoint by hand sees something.
echo "OK" > "$HEALTH_FILE"
chmod 644 "$HEALTH_FILE"
rm -f "${HEALTH_FILE}.off"

# ---------------------------------------------------------------------------
# Stopping a daemon means waiting for it to let go of its port.
#
# `kill` returns as soon as the signal is queued, not when the process has
# exited. Starting the replacement immediately then races the old process's exit,
# and the loser fails to bind with "Address in use" and exits, leaving the
# PREVIOUS daemon listening with the content this script was run to replace. A
# reset that hits that race reports itself done and changes nothing, which is the
# worst thing a reset can do.
#
# The daemon is identified by its pid file rather than by name, which is also the
# handle Part 3 has the learner kill it by.
stop_and_wait() {   # <pid file> <process name> <port it must release>
    if [ -f "$1" ]; then
        kill "$( cat "$1" )" 2>/dev/null || true
    fi
    pkill -x "$2" 2>/dev/null || true     # a daemon started before the pid file existed
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

echo "${NAME}: addressed ${WEB_IP}, serving its name on 80, health endpoint returning 200"
