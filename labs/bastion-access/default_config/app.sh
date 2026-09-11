#!/bin/sh
# Starter config for app: an inner host that runs the site's web service as well
# as sshd.
#
# The web service is here because it is not an SSH service. A default-deny policy
# at the edge has to stop everything the site does not mean to offer, not only
# logins, and a learner who writes SSH rules alone can read what they left open
# off port 80.
set -eu

PREFIXLEN=24
APP_IP="114.2.0.20"
EDGE_INNER_IP="114.2.0.1"

ROOT_PASS="Stavanger-4417"
APP_USER="appops"
APP_PASS="Tromso-6158"

LEAKED_DB_KEY="/home/appops/id_dbops.leaked"

WEB_MARKER="APP-SITE-7C24E9"
WEB_ROOT="/var/www/localhost/htdocs"
WEB_PID="/run/lighttpd.pid"

SSHD_LOG="/var/log/bastion-sshd.log"
SSHD_PID="/run/sshd.pid"
SSHD_CONFIG="/etc/ssh/sshd_config"

ip addr replace "${APP_IP}/${PREFIXLEN}" dev 114-inner
ip link set 114-inner up
ip route replace default via "$EDGE_INNER_IP"

# Part 5 has the learner leave a copy of db's operator key here on purpose, to
# see what a key that nobody pinned can still reach. It is learner-created state,
# so it is removed here: a reset that left it behind would start the next run
# with the lateral-movement test already half done.
rm -f "$LEAKED_DB_KEY"

# Create one account, give it a password, and leave it holding no key.
#
# The account already exists when the lab boots because the site's operators
# already exist; what does not exist is any key, any restriction on where the
# account may be reached from, and any reason it needs a password at all. All
# three are the learner's work.
#
# ~/.ssh is created here with mode 700 and left empty rather than left absent,
# because `docker exec` runs with umask 0022 under a rootful daemon and 0000
# under a rootless one. sshd refuses to read an authorized_keys file whose
# directory is writable by anyone but its owner, and it says nothing about why:
# the login simply falls through to the next method. Fixing the mode here means
# the learner never meets that failure for a reason the handout did not cause.
make_account() {   # <user> <password>
    if ! id -u "$1" >/dev/null 2>&1; then
        adduser -D -s /bin/sh "$1"
    fi
    echo "$1:$2" | chpasswd
    home="$( getent passwd "$1" | cut -d: -f6 )"
    rm -rf "${home}/.ssh"
    mkdir -p "${home}/.ssh"
    chown -R "$1:$1" "${home}/.ssh"
    chmod 700 "${home}/.ssh"
    chmod 755 "$home"
}

make_account "$APP_USER" "$APP_PASS"

# ---------------------------------------------------------------------------
# Stopping a daemon means waiting for it to let go of its port.
#
# `pkill` returns as soon as the signal is queued, not when the process has
# exited. Starting the replacement immediately then races the old process's exit,
# and the loser fails to bind. That failure is close to silent: sshd writes
# "Bind to port 22 on 0.0.0.0 failed: Address in use" into its own log and exits,
# and the PREVIOUS daemon is still listening with the configuration this script
# was run to replace. A reset that hits that race leaves a machine that reports
# itself reset and behaves as it did before, which is the worst thing a reset can
# do.
#
# The daemon is identified by its pid file, not by its name. `pkill -x sshd` does
# not match the OpenSSH listener at all: OpenSSH rewrites its own argv, so the
# process reads as "sshd: /usr/sbin/sshd -D -e [listener]" and an exact-name
# match finds nothing, returns success, and leaves the daemon running.
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

# ---------------------------------------------------------------------------
# sshd, as the site runs it before anybody has thought about who may reach it.
#
# The mini-internet base image ships a hardened sshd_config: PasswordAuthentication
# is no and AllowTcpForwarding is no, because every host in the course network is
# reached with a key. This lab needs the opposite, because turning those off and
# narrowing them is what the learner is graded on. A pristine copy is taken on the
# first run and restored on every run after it, so a learner's edits are replaced
# rather than sed-patched: patching a file somebody else has already edited is how
# a reset leaves a machine in a state neither the handout nor the answer key
# describes.
[ -f "${SSHD_CONFIG}.lab-orig" ] || cp "$SSHD_CONFIG" "${SSHD_CONFIG}.lab-orig"
cp "${SSHD_CONFIG}.lab-orig" "$SSHD_CONFIG"

# sshd uses the FIRST value it obtains for a keyword, so an appended line only
# takes effect where the shipped file left the keyword commented out. The two the
# file sets explicitly are rewritten in place instead.
sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' "$SSHD_CONFIG"
sed -i 's/^[[:space:]]*AllowTcpForwarding[[:space:]].*/AllowTcpForwarding yes/' "$SSHD_CONFIG"
grep -q '^PasswordAuthentication yes' "$SSHD_CONFIG" || echo 'PasswordAuthentication yes' >> "$SSHD_CONFIG"
grep -q '^AllowTcpForwarding yes'     "$SSHD_CONFIG" || echo 'AllowTcpForwarding yes'     >> "$SSHD_CONFIG"

# PermitRootLogin is commented in the shipped file, so the compiled-in default
# (prohibit-password) applies and a password login as root would be refused
# before the lab starts. Saying yes here is what makes Part 1's direct login
# observable.
echo 'PermitRootLogin yes' >> "$SSHD_CONFIG"

echo "root:${ROOT_PASS}" | chpasswd

# Host keys are generated once and kept, rather than regenerated on every reset:
# a reset that changed them would make the next login fail on a host-key
# mismatch, which has nothing to do with anything the lab teaches.
ssh-keygen -A >/dev/null

# -e sends the authentication log to stderr, which is redirected here. That file
# is half of this lab's oracle: a client's exit code says a login failed, and
# this file says which method sshd refused, for which account, and FROM WHICH
# ADDRESS, which is the field every restriction in this lab is written against.
stop_and_wait "$SSHD_PID" sshd 22
mkdir -p /var/log
: > "$SSHD_LOG"
chmod 644 "$SSHD_LOG"
/usr/sbin/sshd -D -e >>"$SSHD_LOG" 2>&1 &

# ---------------------------------------------------------------------------
# The web service. It is the site's reason for existing and it stays reachable
# from the inside for the whole lab; what changes is whether the outside can put
# a packet in front of it.
mkdir -p "$WEB_ROOT"
cat > "${WEB_ROOT}/index.html" <<HTML
<html><body>
<h1>Internal application</h1>
<p>Served by app on the inner segment.</p>
<p>${WEB_MARKER}</p>
</body></html>
HTML
chmod 755 "$WEB_ROOT"
chmod 644 "${WEB_ROOT}/index.html"

# lighttpd drops privileges to server.username and only then opens its logs, so
# an access log this script created as root leaves mod_accesslog with
# "Permission denied" and takes the whole instance down. Removing the file lets
# lighttpd create it as the account that will write to it.
stop_and_wait "$WEB_PID" lighttpd 80
rm -f /var/log/lighttpd/access.log
lighttpd -f /etc/lighttpd/lighttpd.conf

echo "app: addressed; ${APP_USER} reachable by password from anywhere, web service on 80"
