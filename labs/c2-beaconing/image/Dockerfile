# Host image for the malware command-and-control traffic analysis lab.
# One image serves every role on top of the stock mini-internet host image
# (which already ships tcpdump, nmap, netstat and ping):
#   * gw          the gateway. Every packet between the workstations and the
#                 outside crosses it, so it is both the only vantage point the
#                 learner captures from and the only place a policy can be
#                 enforced
#   * ws1 ws2 ws3 the workstations. All three fetch pages and poll a monitoring
#                 endpoint; one of them also runs the implant
#   * ext1 ext2   the two hosts standing in for the internet, carrying five
#                 addresses between them
FROM miniinterneteth/d_host:latest

# tshark is the lab. tcpdump in the base image can capture and can print, but
# every measurement in Part 2 is a per-flow statistic over a whole capture file:
# `-z conv,tcp` for the conversation table and `-T fields` for the timestamp
# columns the interval arithmetic is done on. 4.0 is what Alpine 3.19 carries,
# and the field names the handout uses (frame.time_epoch, tcp.flags.syn,
# tls.handshake.extensions_server_name) are that release's spelling.
#
# python3 runs the controller's listener on ext2. It serves plain HTTP on one
# port and TLS on another from one process, and appends a line per request to
# the file the lab's oracle counts; nothing in the base image can terminate TLS.
#
# openssl generates the controller's self-signed certificate at spawn rather
# than baking one into the image, so the key never sits in a published layer.
#
# lighttpd serves the three legitimate sites. It is used unmodified: the stock
# /etc/lighttpd/lighttpd.conf already serves /var/www/localhost/htdocs and
# already lists index.html as an index file.
#
# nftables is where the learner's whole answer is written. The gateway's egress
# policy is an inet table at the forward hook, and Part 5 replaces its default
# policy rather than adding another rule.
#
# iproute2 gives a full `ip`; the base image's /sbin/ip is a symlink to busybox,
# whose applet has no `ip -o` output format, which the lifecycle scripts parse.
RUN apk add --no-cache \
        tshark \
        python3 \
        openssl \
        lighttpd \
        curl \
        nftables \
        iproute2

# The traffic generators and the controller's listener. All three are generic:
# every address, port, interval and path they use comes from a configuration
# file written by default_config/<device>.sh on the one machine that runs them.
# That split is deliberate. The image is shared by all six containers, so a file
# in it is readable from the gateway; keeping the addresses out of these scripts
# means reading them there tells a learner nothing about which destination the
# implant talks to.
COPY beacon.sh   /usr/local/lib/minilabs/beacon.sh
COPY noise.sh    /usr/local/lib/minilabs/noise.sh
COPY c2listener.py /usr/local/lib/minilabs/c2listener.py
RUN chmod 755 /usr/local/lib/minilabs/beacon.sh \
              /usr/local/lib/minilabs/noise.sh \
              /usr/local/lib/minilabs/c2listener.py

# The directory every generator reads its configuration from, and the one the
# controller writes its record of arrivals into. Created here rather than in a
# starter script so their modes do not depend on the daemon's umask, which
# differs between a rootful and a rootless Docker.
RUN mkdir -p /etc/minilabs /var/log/c2 \
 && chmod 755 /etc/minilabs /var/log/c2
