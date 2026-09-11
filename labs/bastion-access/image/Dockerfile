# Host image for the bastion host and access control lab.
# One image serves every machine on top of the stock mini-internet host image
# (which already ships nmap, netstat, tcpdump, ping and an OpenSSH server):
#   * workstation  the operator's machine, outside the site: the vantage every
#                  sweep is run from, and where the key pairs are generated
#   * edge         the router between the three segments; forwards everything and
#                  filters nothing until Part 2
#   * bastion      the jump host, alone on the DMZ segment
#   * app, db      the two machines behind the router
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip`; the base image's /sbin/ip is a symlink to busybox,
# whose applet has no `ip -o` output format, which every lifecycle script parses.
#
# nftables is where Part 2 is written, on the edge router. The base image ships
# none.
#
# openssh-client is absent from the base image, which carries the server only, so
# without it nothing here could open a session, and neither `ssh -J` nor
# `ssh-keygen` would exist. sshpass drives the non-interactive password logins in
# selftest.sh; the handout never uses it, because a learner types the password
# when ssh asks.
#
# lighttpd is app's web service and curl is how its content is read. The service
# is not an SSH service, which is the point: a default-deny policy at the edge
# has to stop it too.
#
# shadow supplies usermod and chage; busybox's adduser cannot add an existing
# account to a second group, which is what the per-account setup needs.
RUN apk add --no-cache \
        iproute2 nftables \
        openssh-client sshpass \
        lighttpd curl \
        shadow
