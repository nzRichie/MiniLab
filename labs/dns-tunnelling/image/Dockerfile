# Host image for the DNS tunnelling and egress control lab.
# One image serves every role on top of the stock mini-internet host image
# (which already ships tcpdump and ping):
#   * gw         the gateway. Every query between the inside and the outside
#                crosses it, so it is both the vantage point the learner
#                captures from and the place the egress policy is enforced
#   * resolver   named as the campus recursive resolver: the machine that
#                forwards a query on to wherever a name lives, and the machine
#                the learner writes a response policy on in Part 2B
#   * ws1        the compromised workstation the file leaves from; where the
#                learner drives the channel by hand in Part 1
#   * ws2        a second, uncompromised workstation, the legitimate-DNS baseline
#   * pub        named, authoritative for the legitimate zone example.lab
#   * collector  named, authoritative for the operator's zone evil.lab, plus the
#                decoder that reassembles the file from the query names it logs
FROM miniinterneteth/d_host:latest

# bind is named itself, in three roles (resolver, pub, collector). bind-tools
# carries dig, rndc and named-checkconf; the base image ships a dig but not rndc,
# and rndc's control channel only matches when it and named come from the same
# version. No bind-dnssec-tools: signing a zone is the DNS cache-poisoning lab's
# subject, not this one's.
#
# The three bind packages are pinned to the 9.18 series because the handout, the
# answer key and this lab's knowledge base entries name BIND 9.18 by version. If
# the base image moves to a branch carrying 9.20 the pin fails the build here,
# which is where a version change should surface rather than in a handout naming
# a version the containers do not run.
#
# tshark reads the capture the learner takes on the gateway: `-T fields -e
# dns.qry.name` gives the query names one per line, which is what the length and
# character-distribution measurements in Part 1 are done on.
#
# python3 runs the collector's decoder. iproute2 gives a full `ip` (the base
# image's /sbin/ip is BusyBox's applet, which the lifecycle scripts' `ip -o`
# parsing needs). curl proves the general outbound block: a request to a web
# service on the outside is refused, which is why DNS is the only way out.
#
# coreutils is installed for base32. BusyBox has base64 but not base32, and
# base32 is the encoding a learner runs by hand in Part 1: its alphabet is
# A-Z and 2-7, every character of which is a legal DNS label character, so an
# encoded chunk needs no further escaping to sit in a query name. nftables is
# where the gateway's egress policy is written.
RUN apk add --no-cache \
        'bind=~9.18' 'bind-tools=~9.18' 'bind-dnssec-tools=~9.18' \
        tshark python3 iproute2 curl coreutils nftables

# The collector's decoder. It takes no default zone or paths on its command line
# from the image; default_config/collector.sh gives it the zone and the log
# paths from lib.sh. The image is shared by every container including the
# gateway, so keeping the zone out of the script means reading it there tells a
# learner nothing.
COPY tunnel-decode.py /usr/local/lib/minilabs/tunnel-decode.py

# The channel driver used by selftest.sh and reset.sh to move a whole file
# without a human typing every chunk. It takes NO default addresses, zone or
# file: running it still means naming the resolver or collector to send to, the
# zone, and the file. The handout never names it (handout rule 8); a learner
# drives the channel with base32 and dig by hand.
COPY dns-exfil.sh /usr/local/bin/dns-exfil

# The HTTP identity behind the general-outbound block: a one-line web server the
# gateway's starter policy refuses to let an inside host reach, which is what
# makes the point that DNS is the only egress this network leaves open.
COPY web-banner.sh /usr/local/bin/web-banner

RUN chmod 755 /usr/local/lib/minilabs/tunnel-decode.py \
              /usr/local/bin/dns-exfil \
              /usr/local/bin/web-banner \
# named runs as root in these containers, and the directories it writes into are
# given to root to match. Alpine's package ships /var/bind owned by the `named`
# account, which named itself then reports as "directory '/var/bind' is not
# writable" and refuses to load a configuration naming it; the same applies to
# /etc/bind/rndc.key, which arrives mode 640 and named cannot open.
#
# /var/log/tunnel is where the collector's decoder writes. Every mode is set
# explicitly rather than left to the ambient umask: docker exec runs with umask
# 0022 under a rootful daemon and 0000 under a rootless one, so a bare mkdir
# yields 755 on one and 777 on the other.
    && mkdir -p /var/bind/keys /var/run/named /var/log/tunnel \
    && chown -R root:root /var/bind /var/run/named /etc/bind \
    && chmod -R 755 /var/bind /var/run/named /var/log/tunnel \
    && chmod 644 /etc/bind/rndc.key
