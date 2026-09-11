# Host and router image for the NAT and port-forwarding lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships iputils ping, tcpdump and traceroute):
#   * router                    the edge device, started with ip_forward=1; the
#                               only machine the learner writes configuration on
#   * inside-1, inside-2        two clients on the private segment
#   * webserver                 the private-segment service Part 4 publishes
#   * outside                   the host beyond the edge, and the only vantage
#                               that sees what the site's traffic looks like from
#                               the far side
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip`. The base image's /sbin/ip is a symlink to busybox,
# whose applet has neither `ip -o` output (which every lifecycle script parses)
# nor `ip route get`, which is how the outside host is made to say, in one line,
# that it holds no route back into the private prefix.
#
# nftables is where every rule in this lab is written. The base image ships none.
#
# conntrack-tools is the other half of the lab's instrumentation. A NAT rule is
# not a rewrite performed per packet; it is an entry in the connection-tracking
# table that later packets of the same flow follow, and `conntrack -L` is the
# only way to read that table. Without it a learner sees translated packets and
# never sees the mapping that produced them.
#
# lighttpd is the web service on the outside host and on the inside web server,
# and curl is how each one is read. Both are needed on every role: the outside
# host both serves and fetches, and so does the inside segment.
RUN apk add --no-cache \
        iproute2 nftables conntrack-tools \
        lighttpd curl
