# Host image for the centralised logging and incident reconstruction lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships tcpdump, ping, netstat, an OpenSSH server and a util-linux
# logger):
#   * collector  the log server: it receives over TCP and writes a file per
#                source host, and it is the only machine that keeps a copy of
#                what happened anywhere else
#   * admin      the administrator's workstation, and the source of the routine
#                traffic the incident has to be told apart from
#   * web        the public web service, whose request log is the second kind of
#                message the collector has to keep straight
#   * db         the sensitive host: it runs sshd, the incident happens to it,
#                and its local log is the one that gets deleted
FROM miniinterneteth/d_host:latest

# rsyslog is the whole lab. The base image runs no syslog daemon at all, so
# without it `logger` writes to a /dev/log nothing is listening on and every
# message the lab is about is discarded at the moment it is produced. 8.2310 is
# what Alpine 3.19 carries; the RainerScript configuration the handout writes
# (module/input/template/ruleset/action) is rsyslog 7 syntax and up.
#
# logrotate is Part 3's second half. rsyslog can bound a file's size on its own
# through an output channel, but logrotate is the tool a distribution actually
# schedules and the one whose interaction with a running daemon is worth
# learning: it renames the file and something has to tell the daemon to reopen
# it.
#
# openssh-client and sshpass are what make the incident real rather than
# replayed. The base image carries the OpenSSH server but not the client, so
# without these nothing could open a session and every "Failed password" line the
# learner reconstructs from would have to be fabricated with `logger`. sshpass
# supplies the passwords non-interactively; the handout never uses it, because
# the learner never types these logins at all.
#
# lighttpd gives `web` a service that logs through syslog, which is what puts a
# second facility (daemon) and a second program name in the collector's files
# beside sshd's. curl is how its pages are requested.
#
# iproute2 gives a full `ip`; the base image's /sbin/ip is a symlink to busybox,
# whose applet has no `ip -o` output format, which the lifecycle scripts parse.
RUN apk add --no-cache \
        rsyslog logrotate \
        openssh-client sshpass \
        lighttpd curl \
        iproute2

# rsyslog's package creates neither of these and its stock configuration expects
# both: the drop-in directory every rule in this lab is written into, and the
# work directory a queue would spool to. Creating them in the image rather than
# in a starter script means their modes do not depend on the daemon's umask,
# which differs between a rootful and a rootless Docker.
RUN mkdir -p /etc/rsyslog.d /var/lib/rsyslog /var/log/remote \
 && chmod 755 /etc/rsyslog.d /var/lib/rsyslog /var/log/remote
