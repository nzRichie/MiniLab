#!/bin/sh
# Starter config for the server: the machine the whole lab is about.
#
# This is the one starter config in the lab that configures something rather than
# asserting a blank state, and what it configures is a server as a hosting
# provider delivers one. Every setting below is a real default or a real vendor
# habit, and every one of them is something the learner turns off:
#
#   * root reachable over SSH with a password, from anywhere that can route here
#   * a password-authenticated account with no key installed
#   * a public web service and an administrative status endpoint, the second of
#     them bound to every address the machine holds
#   * TCP forwarding allowed to any destination the server can reach
#   * no packet filter at all
#
# Everything is written to survive a second run, because reset.sh re-runs this
# script to rebuild the baseline: config files are restored from a pristine copy
# taken on the first run rather than patched in place, the account the learner
# creates is deleted rather than assumed absent, and every daemon is stopped
# before it is started.
set -eu

PREFIXLEN=24
SERVER_IP="110.1.0.20"
ROUTER_SRV_IP="110.1.0.1"

ROOT_PASS="Trondheim-5182"
ADMIN_USER="opsadmin"

PUBLIC_MARKER="PUBLIC-SITE-4B71A0"
ADMIN_MARKER="ADMIN-STATUS-D93E17"
PUBLIC_WEB_ROOT="/var/www/localhost/htdocs"
ADMIN_WEB_ROOT="/var/www/admin"

ADMIN_CONF="/etc/lighttpd/admin.conf"
ADMIN_PID="/run/lighttpd-admin.pid"
ADMIN_LOG_DIR="/var/log/lighttpd-admin"
ADMIN_PORT=8080
LIGHTTPD_USER="lighttpd"

SSHD_LOG="/var/log/vps-sshd.log"
SSHD_PID="/run/sshd.pid"
PUBLIC_PID="/run/lighttpd.pid"
SSHD_CONFIG="/etc/ssh/sshd_config"

# ---------------------------------------------------------------------------
# 0. Stopping a daemon means waiting for it to let go of its port.
#
# `pkill` returns as soon as the signal is queued, not when the process has
# exited. Starting the replacement immediately then races the old process's exit,
# and the loser fails to bind. That failure is close to silent: sshd writes
# "Bind to port 22 on 0.0.0.0 failed: Address in use" into its own log and exits,
# lighttpd says nothing at all, and in both cases the PREVIOUS daemon is still
# listening with the configuration this script was run to replace. A reset that
# hits that race leaves a server that reports itself reset and behaves as it did
# before, which is the worst thing a reset can do.
# The daemon is identified by its pid file, not by its name. `pkill -x sshd` does
# not match the OpenSSH listener at all: OpenSSH rewrites its own argv, so the
# process reads as "sshd: /usr/sbin/sshd -D -e [listener]" and an exact-name
# match finds nothing, returns success, and leaves the daemon running. Both
# daemons write a pid file, and that file is the handle that works.
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
    # Five seconds and still holding it: stop asking.
    if [ -f "$1" ]; then kill -9 "$( cat "$1" )" 2>/dev/null || true; fi
    pkill -9 -x "$2" 2>/dev/null || true
    sleep 0.5
}

# ---------------------------------------------------------------------------
# 1. The network.
ip addr replace "${SERVER_IP}/${PREFIXLEN}" dev 110-srv
ip link set 110-srv up
ip route replace default via "$ROUTER_SRV_IP"

# ---------------------------------------------------------------------------
# 2. Throw away everything a previous run of the lab configured.
#
# The learner's work lands in four places, and all four are undone here rather
# than anywhere else, so that reset.sh is nothing but "run this script again".
#
# The account goes first: `deluser --remove-home` also takes the authorized_keys
# file installed under it, so Part 2 starts from nothing on the next run.
if id -u "$ADMIN_USER" >/dev/null 2>&1; then
    deluser --remove-home "$ADMIN_USER" >/dev/null 2>&1 || true
fi

# The packet filter. Deleting every table leaves the input hook with no base
# chain at all, which is the kernel's own starting point and is what "no packet
# filter" means: with no chain registered at a hook, nothing is examined and
# nothing is dropped.
nft flush ruleset 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. sshd, as delivered.
#
# The mini-internet base image ships a hardened sshd_config: PasswordAuthentication
# is no and AllowTcpForwarding is no, because every host in the course network is
# reached with a key. This lab needs the opposite, because turning those off is
# what the learner is graded on. A pristine copy is taken on the first run and
# restored on every run after it, so a learner's edits are replaced rather than
# sed-patched: patching a file somebody else has already edited is how a reset
# leaves a machine in a state neither the handout nor the answer key describes.
[ -f "${SSHD_CONFIG}.lab-orig" ] || cp "$SSHD_CONFIG" "${SSHD_CONFIG}.lab-orig"
cp "${SSHD_CONFIG}.lab-orig" "$SSHD_CONFIG"

# sshd uses the FIRST value it obtains for a keyword, so these appended lines only
# take effect where the shipped file left the keyword commented out. The two the
# file sets explicitly are rewritten in place instead.
sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' "$SSHD_CONFIG"
sed -i 's/^[[:space:]]*AllowTcpForwarding[[:space:]].*/AllowTcpForwarding yes/' "$SSHD_CONFIG"
grep -q '^PasswordAuthentication yes' "$SSHD_CONFIG" || echo 'PasswordAuthentication yes' >> "$SSHD_CONFIG"
grep -q '^AllowTcpForwarding yes'     "$SSHD_CONFIG" || echo 'AllowTcpForwarding yes'     >> "$SSHD_CONFIG"

# PermitRootLogin is commented in the shipped file, so the compiled-in default
# (prohibit-password) applies and a password login as root would be refused
# before the lab starts. Saying yes here is what makes Part 1 observable.
echo 'PermitRootLogin yes' >> "$SSHD_CONFIG"

echo "root:${ROOT_PASS}" | chpasswd

# The %wheel line is restored to the commented state Alpine ships, so Part 2's
# one-line change is there to make on every run.
[ -f /etc/sudoers.lab-orig ] || cp /etc/sudoers /etc/sudoers.lab-orig
cp /etc/sudoers.lab-orig /etc/sudoers

# Host keys are generated once and kept, rather than regenerated on every reset:
# a reset that changed them would make the admin station's next login fail on a
# host-key mismatch, which has nothing to do with anything the lab teaches.
ssh-keygen -A >/dev/null

# -e sends the authentication log to stderr, which is redirected here. That file
# is half of this lab's oracle: the outside host's exit code says a login failed,
# and this file says which method sshd refused and from where.
#
# The daemon writes /run/sshd.pid, and that file is the only reliable way to
# reload it. `pgrep -x sshd` lists per-connection children alongside the
# listener, and a SIGHUP aimed by pgrep lands on one of those instead: the file
# on disk then says one thing and the running daemon keeps doing another, with
# nothing on screen to say so.
stop_and_wait "$SSHD_PID" sshd 22
mkdir -p /var/log
: > "$SSHD_LOG"
chmod 644 "$SSHD_LOG"
/usr/sbin/sshd -D -e >>"$SSHD_LOG" 2>&1 &

# ---------------------------------------------------------------------------
# 4. The public web service, on port 80. It must still be reachable from outside
#    when the lab is finished: a learner who hardens the server by making its
#    public service unreachable has not hardened it.
mkdir -p "$PUBLIC_WEB_ROOT"
cat > "${PUBLIC_WEB_ROOT}/index.html" <<EOF
<html><body>
<h1>Public site</h1>
<p>This is what the server is here to serve. It is meant to answer anyone.</p>
<p>${PUBLIC_MARKER}</p>
</body></html>
EOF
chmod 755 "$PUBLIC_WEB_ROOT"
chmod 644 "${PUBLIC_WEB_ROOT}/index.html"
# Both lighttpd instances are stopped here, before either is started, because
# `pkill -x lighttpd` cannot tell them apart: it signals whichever ones are
# running. Starting the public site while the previous run's administrative
# instance is still on 8080 would leave that instance serving the old config.
stop_and_wait "$PUBLIC_PID" lighttpd 80
stop_and_wait "$ADMIN_PID" lighttpd "$ADMIN_PORT"
# Removed rather than truncated. lighttpd drops privileges to server.username and
# only then opens its logs, so a file this script created as root would leave
# mod_accesslog with "Permission denied" and take the whole instance down.
rm -f /var/log/lighttpd/access.log
lighttpd -f /etc/lighttpd/lighttpd.conf

# ---------------------------------------------------------------------------
# 5. The administrative status endpoint, on port 8080. A second lighttpd instance
#    with its own config, pid file and log directory, because two instances
#    sharing a pid file leave the second one unable to say which process to stop.
#
#    It ships with server.bind at 0.0.0.0, which is the mistake Part 4 is about:
#    a page meant for whoever administers the machine, offered on every address
#    the machine holds, including the one the public site is reached on.
#
#    The log directory is owned by the lighttpd account rather than by root.
#    lighttpd opens its error log AFTER dropping privileges, so a root-owned
#    directory makes the instance exit at startup with "opening errorlog ...
#    failed: Permission denied" and take no port at all.
mkdir -p "$ADMIN_WEB_ROOT" "$ADMIN_LOG_DIR"
chown "${LIGHTTPD_USER}:${LIGHTTPD_USER}" "$ADMIN_LOG_DIR"
chmod 755 "$ADMIN_WEB_ROOT" "$ADMIN_LOG_DIR"

cat > "${ADMIN_WEB_ROOT}/index.html" <<EOF
<html><body>
<h1>Server status</h1>
<p>Administrative page. Not for the public site's audience.</p>
<p>${ADMIN_MARKER}</p>
</body></html>
EOF
chmod 644 "${ADMIN_WEB_ROOT}/index.html"

# mod_indexfile and index-file.names are both named explicitly. This config
# shares nothing with /etc/lighttpd/lighttpd.conf, so an instance without them
# has no rule for what to serve when the path is "/" and answers 403 rather than
# the page.
cat > "$ADMIN_CONF" <<EOF
server.modules       = ( "mod_indexfile" )
index-file.names     = ( "index.html" )
server.document-root = "${ADMIN_WEB_ROOT}"
server.port          = ${ADMIN_PORT}
server.bind          = "0.0.0.0"
server.pid-file      = "${ADMIN_PID}"
server.username      = "${LIGHTTPD_USER}"
server.groupname     = "${LIGHTTPD_USER}"
server.errorlog      = "${ADMIN_LOG_DIR}/error.log"
EOF
chmod 644 "$ADMIN_CONF"
[ -f "${ADMIN_CONF}.lab-orig" ] || cp "$ADMIN_CONF" "${ADMIN_CONF}.lab-orig"
lighttpd -f "$ADMIN_CONF"

echo "server: delivered as-is. root reachable by password, three ports on every address, no filter"
