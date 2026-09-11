# Host image for the DNS cache-poisoning lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships tcpdump, ping and dig):
#   * resolver  runs named as a caching resolver; the machine under attack and the
#               one the learner hardens in Part 2
#   * auth      runs named as the authoritative server for uni.lab, behind
#               slow-link, plus the real host's HTTP banner
#   * attacker  runs named as the authoritative server for attack.lab, the
#               spoofer, and the impostor's HTTP banner
#   * victim    asks the resolver and believes what it is told
#   * router    forwards between the campus, the authoritative server and the
#               attacker
FROM miniinterneteth/d_host:latest

# bind is named itself, in both roles. bind-tools carries dig and rndc; the base
# image ships a dig but not rndc, and the two have to come from the same version
# as named for rndc's control channel to match. bind-dnssec-tools carries
# dnssec-keygen and dnssec-verify, which is how Part 2 signs the zone and how the
# learner checks a signature by hand.
#
# python3 is what the three baked tools below are written in. iproute2 gives a
# full `ip` (the base image only has BusyBox's applet). curl is the data-plane
# oracle: it is what says which machine actually answered.
#
# The three bind packages are pinned to the 9.18 series because the handout, the
# solution key and four knowledge-base entries name BIND 9.18 by version, and an
# unpinned `apk add bind` makes that true only for as long as the base image's
# Alpine branch happens to carry it. Alpine 3.19 ships 9.18.44-r0 today; if the
# base image moves to a branch carrying 9.20 the pin fails the build here, which
# is where a version change should surface, rather than shipping a handout that
# names a version the containers do not run.
RUN apk add --no-cache \
        'bind=~9.18' 'bind-tools=~9.18' 'bind-dnssec-tools=~9.18' \
        python3 iproute2 curl

# The off-path spoofer. It takes no default addresses, ports or names: running it
# still means naming the address to forge, the port the resolver is listening for
# an answer on, the question to answer, and what to answer with.
COPY dns-spoof /usr/local/bin/dns-spoof

# The delay in front of the authoritative server, which is the width of the race
# window the whole lab turns on. Its header explains why it exists.
COPY slow-link /usr/local/bin/slow-link

# The two HTTP identities: what curl prints decides which machine answered.
COPY banner-server /usr/local/bin/banner-server

RUN chmod 755 /usr/local/bin/dns-spoof /usr/local/bin/slow-link \
              /usr/local/bin/banner-server \
# named runs as root in these containers, and the directories it writes into are
# given to root to match. Alpine's package ships /var/bind owned by the `named`
# account, which named itself then reports as "directory '/var/bind' is not
# writable" and refuses to load a configuration naming it; the same applies to
# /etc/bind/rndc.key, which arrives mode 640 and named cannot open.
#
# Every mode is set explicitly rather than left to the ambient umask: docker exec
# runs with umask 0022 under a rootful daemon and 0000 under a rootless one, so a
# bare mkdir yields 755 on one and 777 on the other.
    && mkdir -p /var/bind/keys /var/run/named \
    && chown -R root:root /var/bind /var/run/named /etc/bind \
    && chmod -R 755 /var/bind /var/run/named \
    && chmod 644 /etc/bind/rndc.key
