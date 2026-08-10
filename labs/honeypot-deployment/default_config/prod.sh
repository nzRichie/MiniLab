#!/bin/sh
# Starter config for the production host: the machine the whole lab exists to
# keep untouched. It runs the two real services, holds the two markers, and logs
# both in the places the oracles read.
set -eu

PREFIXLEN=24
PROD_IP="106.1.0.20"
ROUTER_PROD_IP="106.1.0.1"

LAB_USER="netadmin"
LAB_PASS="Rotterdam-4417"

PROD_SECRET="PROD-HANDOVER-9F2C41"
PROD_DOC="INTERNAL-ROUTING-PLAN-77D3E8"
PROD_SECRET_FILE="/srv/internal/handover.txt"
PROD_WEB_ROOT="/var/www/localhost/htdocs"
PROD_AUTH_LOG="/var/log/prod-sshd.log"

# Everything below is written to survive a second run, because reset.sh re-runs
# this script to rebuild the baseline: addresses are replaced rather than added,
# the account is created only if absent, and the two daemons are stopped before
# they are started.
ip addr replace "${PROD_IP}/${PREFIXLEN}" dev 106-prod
ip link set 106-prod up
ip route replace default via "$ROUTER_PROD_IP"

# The account the attacker arrives holding a password for. It is an ordinary
# unprivileged account: nothing in this lab turns on privilege escalation, only
# on whether the session lands on this host or on the decoy.
id -u "$LAB_USER" >/dev/null 2>&1 || adduser -D -s /bin/sh "$LAB_USER"
echo "${LAB_USER}:${LAB_PASS}" | chpasswd

# The file Part 1 is about. Mode is set explicitly rather than left to the
# ambient umask, which differs between a rootful and a rootless daemon.
mkdir -p "$( dirname "$PROD_SECRET_FILE" )"
cat > "$PROD_SECRET_FILE" <<EOF
Handover note, internal only.
Do not copy this file off the host.

  token: ${PROD_SECRET}
EOF
chmod 755 "$( dirname "$PROD_SECRET_FILE" )"
chmod 644 "$PROD_SECRET_FILE"

# sshd. The mini-internet base image ships PasswordAuthentication no, because
# every host in the course network is reached with a key. This lab needs the
# opposite: the attacker holds a password and nothing else, and Cowrie's whole
# deception depends on the real service and the decoy accepting the same kind of
# credential. Without this line the attacker is refused with "Permission denied
# (publickey,keyboard-interactive)" and Part 1 never starts.
sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' /etc/ssh/sshd_config
grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config \
    || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

# Host keys are generated at spawn rather than baked into the image, so every
# spawn of this lab presents a different key and a learner's known_hosts from a
# previous run cannot make the second login fail for the wrong reason.
#
# -e sends the authentication log to stderr, which is redirected here. That file
# is the Part 2 oracle: a successful attacker login on the real host leaves an
# "Accepted password" line in it, and a redirected one leaves nothing.
ssh-keygen -A >/dev/null
mkdir -p /var/log
pkill -x sshd 2>/dev/null || true
: > "$PROD_AUTH_LOG"
chmod 644 "$PROD_AUTH_LOG"
/usr/sbin/sshd -D -e >>"$PROD_AUTH_LOG" 2>&1 &

# The internal web service. Part 3's pivot is about reaching this document from
# a host that has no business reading it, so its access log is the second oracle:
# it records the source address of whatever fetched the page.
mkdir -p "$PROD_WEB_ROOT" /var/log/lighttpd
cat > "${PROD_WEB_ROOT}/internal.html" <<EOF
<html><body>
<h1>Internal routing plan</h1>
<p>Classification: internal. Do not serve outside the production segment.</p>
<p>${PROD_DOC}</p>
</body></html>
EOF
cat > "${PROD_WEB_ROOT}/index.html" <<EOF
<html><body><h1>Production</h1><p>Nothing to see here.</p></body></html>
EOF
chmod 755 "$PROD_WEB_ROOT" /var/log/lighttpd
chmod 644 "${PROD_WEB_ROOT}/internal.html" "${PROD_WEB_ROOT}/index.html"
pkill -x lighttpd 2>/dev/null || true
# Removed rather than truncated. lighttpd drops privileges to its own account
# after startup and then opens its access log, so a file this script created
# would be owned by root and mod_accesslog would fail with "Permission denied"
# and take the whole server down with it. Deleting it lets lighttpd create it as
# the user that has to write it, and gives reset.sh the empty log it needs.
rm -f /var/log/lighttpd/access.log
lighttpd -f /etc/lighttpd/lighttpd.conf

echo "prod: sshd and lighttpd up, handover note and internal document in place"
