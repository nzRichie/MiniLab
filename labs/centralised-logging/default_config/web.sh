#!/bin/bash
# Starter configuration for the public web service.
#
# Its job in the lab is to produce a second kind of message. lighttpd is
# configured to log through syslog rather than to a file of its own, so its
# request lines travel the same path as sshd's authentication lines and land
# beside them, carrying a different facility, a different severity and a
# different program name. Telling those apart at the collector is what the
# facility and severity questions are asked against.
#
# It runs no SSH server. It is the machine the incident's login attempts come
# FROM, and a machine that answers nothing on port 22 is one less thing to
# confuse the direction of a session with.
set -e

ip addr flush dev 113-S1 2>/dev/null || true
ip addr add 113.0.0.30/24 dev 113-S1
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
# The web service.
#
# server.errorlog-use-syslog and accesslog.use-syslog are what put lighttpd's
# output on the same path as everything else. Without them lighttpd writes to
# files of its own under /var/log/lighttpd, which no forwarding rule in this lab
# would ever pick up: rsyslog forwards what arrives on /dev/log, not what other
# programs write to their own files.
mkdir -p /var/www/localhost/htdocs
chmod 755 /var/www/localhost/htdocs

cat > /var/www/localhost/htdocs/index.html <<'HTML'
WEB-SITE-5A71C9
HTML
chmod 644 /var/www/localhost/htdocs/index.html

cat > /etc/lighttpd/lighttpd.conf <<'CONF'
server.document-root = "/var/www/localhost/htdocs"
server.port          = 80
server.pid-file      = "/run/lighttpd.pid"
server.modules       = ( "mod_accesslog", "mod_indexfile" )
index-file.names     = ( "index.html" )
mimetype.assign      = ( ".html" => "text/html" )

# Send both of lighttpd's logs to syslog instead of to files of its own.
server.errorlog-use-syslog = "enable"
accesslog.use-syslog       = "enable"
CONF
chmod 644 /etc/lighttpd/lighttpd.conf

pkill -x lighttpd 2>/dev/null || true
sleep 0.4
lighttpd -f /etc/lighttpd/lighttpd.conf
