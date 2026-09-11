# Host and router image for the addressing-and-static-routing lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships iputils ping, tcpdump, traceroute and busybox ipcalc):
#   * west-1, west-2, mid-1, mid-2, east-1, east-2  the six hosts the learner
#     addresses and gives a default route
#   * west-router, east-router  the two Linux routers, started with
#     net.ipv4.ip_forward=1, that the learner gives static routes
FROM miniinterneteth/d_host:latest

# iproute2 is the whole point of this image. The base image's /sbin/ip is a
# symlink to busybox, whose ip applet has no `ip route get`, no `ip route flush
# cache` and no `ip -o` output format. All three are load-bearing here:
# `ip route get` is the only command that reports a cached route exception
# installed by an ICMP redirect, `ip route flush cache` is what clears one, and
# the lifecycle scripts parse `ip -o` output.
#
# net-tools carries route, netstat and ifconfig. The lab teaches `ip` and nothing
# else, but it has the learner print the same routing table with `route -n` once,
# to see that the two commands report the same table in different columns; that
# comparison needs the real net-tools route, not the busybox applet, because the
# busybox one prints neither the Flags column nor the same header.
RUN apk add --no-cache iproute2 net-tools
