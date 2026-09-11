#!/bin/bash
# Starter configuration for the administrator's workstation.
#
# It is where the routine work in this lab comes from: the daily login to the
# sensitive host, and the requests against the web service. Its role in the
# reconstruction is to be the thing the incident has to be told apart from, so
# every message it produces is one an ordinary working day produces too.
#
# It also runs an SSH server, because the last step of the incident is a login
# INTO this machine from somewhere it never normally comes from.
set -e

ip addr flush dev 113-S1 2>/dev/null || true
ip addr add 113.0.0.20/24 dev 113-S1
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
# The SSH server and the account the last step of the incident authenticates as.
# The reasoning behind both settings is in db.sh, which configures the same two.
adduser -D -s /bin/sh ops 2>/dev/null || true
echo 'ops:Wint3rMoss?' | chpasswd

sed -i 's/^ *#* *PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config \
    || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
sed -i 's/^ *#* *PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
grep -q '^PermitRootLogin no' /etc/ssh/sshd_config \
    || echo 'PermitRootLogin no' >> /etc/ssh/sshd_config

ssh-keygen -A >/dev/null 2>&1

pkill -x sshd 2>/dev/null || true
sleep 0.4
/usr/sbin/sshd
