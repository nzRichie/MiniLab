# Host image for the authoritative DNS, zone authoring and delegation lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships tcpdump, ping and a dig):
#   root       named, authoritative for the three given zones above uni.lab
#   primary    named, and the machine the learner authors the forward and the
#              reverse zone on
#   secondary  named, and the machine that transfers the forward zone
#   sub        named, authoritative for the child zone the parent delegates to
#   client     named as a recursive resolver, plus every measuring tool the lab uses
FROM miniinterneteth/d_host:latest

# bind is named itself, in all five roles. bind-tools carries dig, rndc,
# named-checkzone and named-checkconf; the base image ships a dig but none of the
# other three, and rndc's control channel only matches when it and named come
# from the same version.
#
# No DNSSEC package is installed. Signing a zone is the DNS cache-poisoning lab's
# subject, and a `bind-dnssec-tools` here would put dnssec-keygen in front of a
# learner whose zone is not signed and is not going to be.
#
# python3 is what the banner server below is written in. iproute2 gives a full
# `ip` (the base image only has BusyBox's applet, which has no `ip -6 addr`
# handling this lab can rely on). curl is the one check in the lab that is not a
# DNS answer: it says whether a name resolved through the whole chain reached the
# machine the record named.
#
# The two bind packages are pinned to the 9.18 series because the handout, the
# answer key and this lab's knowledge base entries name BIND 9.18 by version, and
# an unpinned `apk add bind` makes that true only for as long as the base image's
# Alpine branch happens to carry it. If the base image moves to a branch carrying
# 9.20 the pin fails the build here, which is where a version change should
# surface, rather than shipping a handout that names a version the containers do
# not run.
RUN apk add --no-cache \
        'bind=~9.18' 'bind-tools=~9.18' \
        python3 iproute2 curl

# The HTTP identity of a web name: the one oracle in this lab that is not a DNS
# answer. It takes no default string, so each machine names itself.
COPY banner-server /usr/local/bin/banner-server

RUN chmod 755 /usr/local/bin/banner-server \
# named runs as root in these containers, and the directories it writes into are
# given to root to match. Alpine's package ships /var/bind owned by the `named`
# account, which named itself then reports as "directory '/var/bind' is not
# writable" and refuses to load a configuration naming it; the same applies to
# /etc/bind/rndc.key, which arrives mode 640 and named cannot open.
#
# /var/bind/secondary is where the secondary writes the copy of the zone it
# transfers. named creates the file, so the directory has to be writable before
# the first transfer, not after it.
#
# Every mode is set explicitly rather than left to the ambient umask: docker exec
# runs with umask 0022 under a rootful daemon and 0000 under a rootless one, so a
# bare mkdir yields 755 on one and 777 on the other.
    && mkdir -p /var/bind/secondary /var/run/named /var/log \
    && chown -R root:root /var/bind /var/run/named /etc/bind \
    && chmod -R 755 /var/bind /var/run/named \
    && chmod 644 /etc/bind/rndc.key
