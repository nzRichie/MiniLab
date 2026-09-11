# Host image for the firewalling and intrusion detection lab.
# One image serves every role on top of the stock mini-internet host image
# (which already ships tcpdump, ping and traceroute):
#   * server    the machine under attack and the only one the learner
#               configures: three listeners, a packet filter and Suricata
#   * client    the internal workstation whose telnet access has to survive
#               every rule the learner writes
#   * router    forwards between the two segments and translates nothing
#   * attacker  the outside machine, with an address on each outside prefix
#   * customer  the outside reader of the public web site
FROM miniinterneteth/d_host:latest

# suricata is the lab. The Alpine 3.19 package is 7.0.2, built with NFQueue
# support, which is what Part 3 needs: without it `suricata -q 0` exits at
# startup and there is no inline mode to teach. It also ships a rule set of
# about fifty thousand signatures in /var/lib/suricata/rules/suricata.rules,
# which is why the learner's own file is an ADDITION to rule-files rather than a
# replacement for it, and why every start takes twenty seconds or more.
#
# python3 runs suricatasc, the client that tells a running Suricata to reload
# its rules. In 7.0.2 it is a Python script, so a Suricata without python3 has
# no way to pick up an edited rule short of a restart.
#
# nmap and nmap-nping are the attacker's tools. nping crafts one TCP SYN at a
# time with the flags named on the command line and prints what came back, which
# is the measurement every step of Part 1 is read off. Alpine carries no hping3.
#
# busybox-extras supplies telnetd and the telnet client. The telnet service is
# the exposure the whole lab is written around: it authenticates a user and
# carries the session in cleartext, and it is the one listener that has no
# business answering an address outside the site.
#
# iptables is where Part 1's whole answer is written, and Part 3 needs it again
# for the rule that hands packets to Suricata.
#
# lighttpd serves the public web site, used unmodified: the stock
# /etc/lighttpd/lighttpd.conf already serves /var/www/localhost/htdocs and
# already lists index.html as an index file. curl is how the two clients read
# it, and it is the measurement that says a rule stayed narrow.
#
# iproute2 gives a full `ip`; the base image's /sbin/ip is a symlink to busybox,
# whose applet has no `ip -o` output format, which the lifecycle scripts parse.
#
# nano is the editor the learner opens suricata.yaml with, twice. The base image
# has busybox vi and nothing else, and a modal editor is a bad thing to put
# between a student and a two-line configuration change.
RUN apk add --no-cache \
        suricata \
        python3 \
        nmap nmap-nping \
        busybox-extras \
        iptables \
        lighttpd \
        curl \
        iproute2 \
        nano

# The copy reset.sh restores. The learner edits /etc/suricata/suricata.yaml
# twice, and both edits are made with an editor rather than by a script, so
# there is no inverse to apply. Resetting the lab therefore means putting back
# the file as the package shipped it, and the only moment that file is
# guaranteed untouched is here.
RUN mkdir -p /usr/local/share/minilabs \
 && cp /etc/suricata/suricata.yaml /usr/local/share/minilabs/suricata.yaml.orig \
 && chmod 755 /usr/local/share/minilabs \
 && chmod 644 /usr/local/share/minilabs/suricata.yaml.orig

# Suricata's log directory, and the web site's document root. Created here
# rather than in a starter script so their modes do not depend on the daemon's
# umask, which is 0022 under a rootful Docker and 0000 under a rootless one.
RUN mkdir -p /var/log/suricata /var/www/localhost/htdocs \
 && chmod 755 /var/log/suricata /var/www/localhost/htdocs
