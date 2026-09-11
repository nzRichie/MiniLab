# Host image for the VPS provisioning and hardening lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships nmap, netstat, tcpdump, ping and an OpenSSH server):
#   * server   the machine being hardened: sshd, a public web service and an
#              administrative status endpoint, none of them configured well
#   * admin    the administrative client, which holds the key pair and is the
#              one source SSH is meant to accept once the lab is finished
#   * outside  the vantage every port sweep is run from
#   * router   forwards between the three segments and filters nothing
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip`; the base image's /sbin/ip is a symlink to busybox,
# whose applet has no `ip -o` output format, which every lifecycle script parses.
#
# nftables is where Part 5 is written. The base image ships none.
#
# openssh-client is absent from the base image, which carries the server only, so
# without it neither the admin station nor the outside host could open a session,
# and neither `ssh -L` nor `ssh-keygen`'s client side would exist. sshpass drives
# the non-interactive password logins in selftest.sh; the handout never uses it,
# because a learner types the password when ssh asks.
#
# lighttpd is both web services and curl is how their content is read. sudo is
# the privilege escalation Part 2 configures: Alpine ships /etc/sudoers with the
# %wheel line present and commented, which is exactly the one-line change the
# lab is about.
RUN apk add --no-cache \
        iproute2 nftables \
        openssh-client sshpass \
        lighttpd curl \
        sudo
