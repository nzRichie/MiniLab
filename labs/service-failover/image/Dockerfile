# Host image for the service availability and failover lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships nmap, netstat, tcpdump and ping):
#   * client       the only machine on the front segment; every number this lab
#                  is graded on is measured from here
#   * proxy        the reverse proxy, and the only machine with a route to both
#                  segments. The whole exercise is written in its config file
#   * web1, web2   the pool: two backends holding the same site, each serving its
#                  own name so a request can be traced to the one that answered
FROM miniinterneteth/d_host:latest

# haproxy is the lab. 2.8 is what Alpine 3.19 carries and it is an LTS branch, so
# the configuration keywords the learner writes (option httpchk, http-check
# send/expect, retries, option redispatch, timeout connect) are the current
# spelling rather than a deprecated one. nginx was not an option: its open-source
# build has no active health check at all, only passive max_fails counting, and
# an active check is what Part 2 is about.
#
# lighttpd is each backend's web service, and the base image ships none. It is
# used unmodified: the stock /etc/lighttpd/lighttpd.conf already serves
# /var/www/localhost/htdocs, already lists index.html as an index file, and
# already writes /run/lighttpd.pid, which is the pid the learner kills in Part 3.
#
# socat is how the runtime API socket is spoken to. HAProxy's stats socket is a
# UNIX socket that takes one line and replies with one document, so `show stat`
# and `set server` both need something that can write to it and read the answer
# back; nothing in the base image can.
#
# curl is the client's instrument. Every measurement in this lab is a curl exit
# with -w '%{http_code} %{time_total}', because the two numbers the lab is graded
# on are how many requests failed and how long the slowest one took.
#
# nftables is Part 4's blackhole. Dropping a backend's inbound traffic rather
# than stopping its service is what makes a connection attempt time out instead
# of being refused, and telling those two failures apart is the part.
#
# iproute2 gives a full `ip`; the base image's /sbin/ip is a symlink to busybox,
# whose applet has no `ip -o` output format, which the lifecycle scripts parse.
RUN apk add --no-cache \
        haproxy \
        lighttpd \
        socat curl \
        nftables \
        iproute2

# HAProxy's package creates neither of these and the configuration expects both:
# the directory the runtime API socket is bound in, and the chroot directory the
# stock global section points at. Creating them in the image rather than in a
# starter script means their modes do not depend on the daemon's umask, which
# differs between a rootful and a rootless Docker.
RUN mkdir -p /run/haproxy /var/lib/haproxy \
 && chmod 755 /run/haproxy /var/lib/haproxy
