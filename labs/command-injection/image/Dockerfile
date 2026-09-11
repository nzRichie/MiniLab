# Host image for the command injection and containment lab.
# One image serves every role on top of the stock mini-internet host image
# (which already ships tcpdump, curl's absence aside, and a setuid /bin/ping):
#   * gw        the gateway between the appliance's segment and the outside, and
#               the machine the egress allowlist is written on in Part 2C
#   * web       the appliance: lighttpd serving the public network-tools page,
#               and the machine Parts 2A and 2B are worked on
#   * ops       the operator's workstation, the legitimate caller of the page
#   * mon       the upstream monitor the appliance's own probes are aimed at,
#               and the liveness target every defence stage is measured against
#   * attacker  the outside machine that calls the page and holds the listener
FROM miniinterneteth/d_host:latest AS build

# The vulnerable program is compiled here rather than downloaded, so the source
# the handout quotes and the binary the learner attacks are the same build. The
# compiler stays in this stage and never reaches the shipped image.
#
# -O0 keeps the generated code close to the source a learner reads at
# /usr/local/share/minilabs/diag.c. -static removes the runtime link on libc,
# which matters because Part 2A changes which account executes the binary and a
# static binary cannot fail for a reason that has nothing to do with the lab.
RUN apk add --no-cache gcc musl-dev
COPY diag.c /src/diag.c
RUN mkdir -p /out && gcc -static -O0 -Wall -o /out/diag.cgi /src/diag.c

FROM miniinterneteth/d_host:latest

# lighttpd 1.4.85 serves the page and runs the CGI through mod_cgi. It is the
# server whose server.username directive Part 2A sets, which is the whole of
# that stage's configuration.
#
# curl is how every request in this lab is sent: --data-urlencode is what lets a
# learner put a semicolon and a space into a query parameter without hand-writing
# percent escapes. The base image has no curl.
#
# iproute2 gives a full `ip`; the base image's /sbin/ip is BusyBox's applet,
# whose output the lifecycle scripts' `ip -o` parsing needs. nftables is where
# the egress allowlist is written in Part 2C.
RUN apk add --no-cache lighttpd curl iproute2 nftables

# The service account Part 2A hands the web server. It has no home directory and
# /sbin/nologin as its shell, because nothing ever logs in as it: lighttpd
# setuid()s to it after binding port 80. The uid and gid are pinned at 1001 so
# the handout and the answer key can name the `uid=1001(svc)` line the learner
# reads back out of the injected `id`.
RUN addgroup -g 1001 svc \
    && adduser -D -H -u 1001 -G svc -s /sbin/nologin svc

# The pristine copy of the vulnerable CGI, plus its source. default_config/web.sh
# installs the binary into the webroot from here on every spawn and every reset,
# so a learner who deleted or overwrote it gets the original back. The source
# sits beside it because Part 1 has the learner read the one line that is the
# bug, in the container, rather than take the handout's word for it.
RUN mkdir -p /usr/local/lib/minilabs /usr/local/share/minilabs
COPY --from=build /out/diag.cgi /usr/local/lib/minilabs/diag.cgi
COPY diag.c /usr/local/share/minilabs/diag.c

# Every mode is set explicitly rather than left to the ambient umask: docker exec
# runs with umask 0022 under a rootful daemon and 0000 under a rootless one, so a
# bare mkdir yields 755 on one and 777 on the other. /var/log/lighttpd is created
# here because lighttpd opens its error log before it drops privilege and refuses
# to start if the directory is missing.
RUN chmod 755 /usr/local/lib/minilabs/diag.cgi \
    && chmod 644 /usr/local/share/minilabs/diag.c \
    && mkdir -p /var/log/lighttpd /var/www/html /var/www/cgi-bin \
    && chmod 755 /var/log/lighttpd /var/www /var/www/html /var/www/cgi-bin
