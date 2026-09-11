#!/bin/bash
# Starter configuration for the sensitive host.
#
# This is the machine the incident happens to. It runs an SSH server that accepts
# passwords, holds one unprivileged account, and writes everything it produces to
# a file on its own disk and to nowhere else. That last part is the lab: when the
# incident deletes this file, everything the machine recorded about what happened
# to it is gone, unless the learner arranged for a copy somewhere else first.
#
# reset.sh re-runs this script, so it also puts the local log file back and
# deletes the forwarding rule the learner wrote.
set -e

ip addr flush dev 113-S1 2>/dev/null || true
ip addr add 113.0.0.40/24 dev 113-S1
ip link set dev 113-S1 up

# ---------------------------------------------------------------------------
# The base rsyslog configuration, identical on all four machines. See
# collector.sh for why imuxsock is loaded and imklog is not, and for why the
# default file template records the facility and the severity nowhere.
cat > /etc/rsyslog.conf <<'CONF'
module(load="imuxsock")

global(workDirectory="/var/lib/rsyslog")

# Everything this machine produces, in one file on this machine's own disk.
*.*   action(type="omfile" file="/var/log/messages")

# Local additions. Every rule this lab asks you to write goes in a file here,
# and rsyslog reads them in filename order.
include(file="/etc/rsyslog.d/*.conf" mode="optional")
CONF
chmod 644 /etc/rsyslog.conf

rm -f /etc/rsyslog.d/*.conf

# Part 1 has the learner file one facility into a second local file of its own,
# so the delivered state has to be one where that file does not exist yet.
rm -f /var/log/auth-warn.log

: > /var/log/messages
chmod 640 /var/log/messages

# rsyslogd refuses to start while its pid file names a live process, and it does
# not remove that file until it has finished shutting down. A fixed sleep before
# starting the replacement is a race a busy machine loses, and the failure it
# produces leaves this machine running the configuration it had before.
pkill -x rsyslogd 2>/dev/null || true
n=0
while pgrep -x rsyslogd >/dev/null 2>&1 && [ $n -lt 40 ]; do
    sleep 0.25
    n=$(( n + 1 ))
done
rm -f /var/run/rsyslogd.pid
rsyslogd

# ---------------------------------------------------------------------------
# The SSH server, and the account the incident authenticates as.
#
# PasswordAuthentication is turned on, which the stock Alpine configuration turns
# off. It is on because a failed password is the event this lab reconstructs, and
# OpenSSH writes a "Failed password" line only for an authentication method it
# actually offered; with keys only, six wrong guesses produce six lines that name
# no account and no method.
#
# PermitRootLogin stays off. Nothing in the incident needs root over the network,
# and a lab that leaves root reachable by password teaches the wrong default in
# passing.
adduser -D -s /bin/sh dbadmin 2>/dev/null || true
echo 'dbadmin:Th4mesRiver!' | chpasswd

sed -i 's/^ *#* *PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config \
    || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
sed -i 's/^ *#* *PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
grep -q '^PermitRootLogin no' /etc/ssh/sshd_config \
    || echo 'PermitRootLogin no' >> /etc/ssh/sshd_config

# Host keys are generated on first boot rather than baked into the image, so two
# machines built from the same image do not present the same key. ssh-keygen -A
# creates only the key types that are missing, so re-running this on a reset
# leaves the keys the incident already recorded alone.
ssh-keygen -A >/dev/null 2>&1

pkill -x sshd 2>/dev/null || true
sleep 0.4
/usr/sbin/sshd
