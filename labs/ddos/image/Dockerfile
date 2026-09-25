# Host image for the ddos lab. One image serves every role on top of the stock
# mini-internet host image (which already ships tcpdump, nping, ping, dig and
# iperf3):
#
#   router     forwards between the three legs, carries both shapers, and is
#              where every filter and every sysctl the learner writes goes
#   server     the victim, attacked at three layers from one address: lighttpd
#              on tcp/80, iperf3 on tcp/5201, and BIND authoritative for lab. on
#              udp/53
#   admin      the site's workstation on the field leg: the measurement. Runs
#              `probe`, which is iperf3, curl, dig and ping and nothing else
#   host1..4   the four flood sources, driven from the console over SSH
#   host5      the DNS reflector: dnsmasq with four TXT record sets
#   host6      the NTP reflector: ntpsec answering a mode-6 control query
#   c2         the console every stage is driven from
#   loader     lighttpd serving the flood tool's source text, so a learner can
#              read exactly what the thing they are running sends
FROM miniinterneteth/d_host:latest

# iproute2   tc for the two shapers, ss for the half-open count, nstat for the
#            per-namespace counters the uRPF and syncookie readings come off.
#            The base image's /sbin/ip is BusyBox's applet, which has none of
#            these.
# iptables   the learner's source blocks on the router and the RST drop on each
#            source. The base image ships none.
# scapy      the by-hand packets: the twelve-byte NTP control query and the
#            spoofed TCP SYN, both of which the handout has the learner build
#            field by field rather than run a tool for. Pulls python3, which is
#            what `flood` and `probe` are written in.
# dnsmasq    the DNS reflector (2.90).
# ntpsec     the NTP reflector (1.2.3). The classic monlist vector is gone from
#            every Alpine NTP package; mode-6 readvar is what replaced it.
# bind       the victim's authoritative server, pinned to the 9.18 series the
#            other DNS labs name by version. bind-tools carries rndc and a dig
#            that matches it.
# lighttpd   the victim's web service and the loader's file service.
# curl       the admin's web probe reads an HTTP status code with -w
#            '%{http_code}'; the base image ships wget, which cannot.
# openssh-client + sshpass  the console drives each source non-interactively.
#            The base image ships the server only.
RUN apk add --no-cache \
        iproute2 \
        iptables \
        scapy \
        dnsmasq \
        ntpsec \
        'bind=~9.18' 'bind-tools=~9.18' \
        lighttpd \
        curl \
        openssh-client \
        sshpass \
 && mkdir -p /var/lib/ntpsec

# A client config for the lab's own addresses, so an ssh in this lab is one
# readable command rather than one command carrying five -o flags. The stock
# /etc/ssh/ssh_config is a single `Include /etc/ssh/ssh_config.d/*.conf`, so a
# drop-in file is the whole of the change. Scoped to Host 129.*, which is this
# lab's own /8 and the only place any of it is true:
#
#   StrictHostKeyChecking no, UserKnownHostsFile /dev/null
#       each source regenerates its host key on every spawn
#   LogLevel ERROR
#       drops the "Permanently added ..." line those two settings print on every
#       connection. It does not hide an authentication failure
#   PreferredAuthentications password, PubkeyAuthentication no
#       no account in this lab has an authorized key
#   ConnectTimeout 4
#       a source that is wedged must not hold up the other three
RUN mkdir -p /etc/ssh/ssh_config.d \
 && printf '%s\n' \
        'Host 129.*' \
        '    StrictHostKeyChecking no' \
        '    UserKnownHostsFile /dev/null' \
        '    LogLevel ERROR' \
        '    PreferredAuthentications password' \
        '    PubkeyAuthentication no' \
        '    ConnectTimeout 4' \
        > /etc/ssh/ssh_config.d/10-minilabs.conf \
 && chmod 755 /etc/ssh/ssh_config.d \
 && chmod 644 /etc/ssh/ssh_config.d/10-minilabs.conf

# The two instruments. `flood` is the bounded flood generator every stage is run
# with: it takes NO defaults for anything, so a run names the reflector, the
# forged source, the target, the rate and the count. --pps and --count are both
# mandatory, because unpaced its UDP loop reaches over 100000 packets a second
# and the count is what bounds a run without anybody having to kill it.
#
# `probe` is the admin's measurement: iperf3, curl, dig and ping, each printed
# before it runs, with one line per result written to a state file that
# status.sh reads.
COPY flood /usr/local/bin/flood
COPY probe /usr/local/bin/probe
RUN chmod 755 /usr/local/bin/flood /usr/local/bin/probe

# The directories the lab writes into, created here so their modes do not depend
# on the daemon's umask, which differs between a rootful and a rootless Docker.
#
# named runs as root in these containers and the directories it writes into are
# given to root to match. Alpine's bind package ships /var/bind owned by the
# `named` account, which named then reports as "directory '/var/bind' is not
# writable" and refuses to load a configuration naming it; /etc/bind/rndc.key
# arrives mode 640, which named cannot open either.
RUN mkdir -p /var/lib/minilabs /run/minilabs /var/log/lighttpd /var/bind /var/run/named \
 && chmod 755 /var/lib/minilabs /run/minilabs /var/log/lighttpd \
 && chown -R root:root /var/bind /var/run/named /etc/bind \
 && chmod -R 755 /var/bind /var/run/named \
 && chmod 644 /etc/bind/rndc.key
