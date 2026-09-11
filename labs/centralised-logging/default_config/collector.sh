#!/bin/bash
# Starter configuration for the log server.
#
# It arrives addressed, running rsyslog, and deaf. The daemon listens on no
# network port and holds no rule for anything arriving from another machine, so
# at spawn the collector collects nothing and the directory it is meant to fill
# is empty. Both halves of that are the learner's to fix.
#
# reset.sh re-runs this script, so its second job is to throw the learner's work
# away: the drop-in directory is emptied, the per-host files are deleted and the
# rotation policy is removed.
set -e

ip addr flush dev 113-S1 2>/dev/null || true
ip addr add 113.0.0.10/24 dev 113-S1
ip link set dev 113-S1 up

# Every machine in this lab is one hop from every other, so the connected route
# the kernel installs alongside the address is the whole of what this host needs.
# No default route: nothing in this lab is beyond the segment.

# ---------------------------------------------------------------------------
# The base rsyslog configuration, identical on all four machines.
#
# imuxsock is the module that opens /dev/log, which is the socket the C library's
# syslog(3) writes to and therefore where every message from `logger`, sshd and
# lighttpd arrives. Without it a message is discarded by the kernel at the moment
# it is produced and nothing anywhere records that it existed.
#
# imklog is deliberately NOT loaded. It reads the kernel ring buffer through
# /proc/kmsg, which in a container is the host's buffer and not this machine's,
# so loading it would put messages from the machine running the lab into the
# lab's own logs.
#
# The one output rule writes everything to a file on this machine's own disk,
# with rsyslog's default file template. That template records the time, the
# hostname, the program and the message, and it records neither the facility nor
# the severity: both were used to decide that this rule matched and neither is
# kept. Part 1 is built on noticing that.
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

# Undo whatever the learner wrote. An empty drop-in directory is the delivered
# state, and it is what makes `reset` mean something on this machine.
rm -f /etc/rsyslog.d/*.conf

# The per-host directory exists and is empty. It exists so the learner's first
# template has somewhere to write and does not fail on a missing path; it is
# empty because nothing has been received.
#
# The mode is set explicitly rather than left to `mkdir`. docker exec runs with
# umask 0022 under a rootful daemon and 0000 under a rootless one, so a bare
# mkdir gives 755 on one machine and 777 on another.
mkdir -p /var/log/remote
rm -rf /var/log/remote/*
chmod 755 /var/log/remote

# The rotation policy is the learner's to write, so it is removed here along with
# logrotate's record of what it has already rotated. Leaving the state file
# behind would make the learner's first `logrotate` run skip a file it has never
# actually rotated in this session.
rm -f /etc/logrotate.d/remote /var/lib/logrotate.status

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
