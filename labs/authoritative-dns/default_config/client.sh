#!/bin/sh
# Starter config: the machine every query in this lab is sent from.
#
# It runs named as a recursive resolver and holds no zone of its own. The only
# thing it is told is where the root server is, in /var/bind/root.hints, which is
# how a resolver on the real internet starts as well: a hints file naming the
# root servers, and everything below that learned by following referrals.
#
# This machine is given whole and the learner never edits it. It is the
# measuring instrument, not the subject: when a name fails to resolve here, the
# fault is in one of the three servers the learner is building.
set -e

ip addr replace 115.0.0.40/24 dev 115-S1
ip -6 addr replace fd00:115::40/64 dev 115-S1
ip link set 115-S1 up

mkdir -p /var/bind /var/run/named
chmod 755 /var/bind /var/run/named

# The hints file. Two records: the root's name-server name, and its address.
# Everything else this resolver ever learns comes from following referrals down
# from here.
cat > /var/bind/root.hints <<'HINTS'
.               3600000     IN  NS  ns.root-lab.
ns.root-lab.    3600000     IN  A       115.0.0.2
ns.root-lab.    3600000     IN  AAAA    fd00:115::2
HINTS
chmod 644 /var/bind/root.hints

cat > /etc/bind/named.conf <<'CONF'
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { 127.0.0.1; 115.0.0.40; };
    listen-on-v6 port 53 { ::1; fd00:115::40; };
    allow-query { any; };
    // A resolver: it looks names up on the asker's behalf, starting at the root.
    recursion yes;
    allow-recursion { any; };
    // Nothing in this lab is signed. With validation off there is no trust
    // anchor to load and nothing to check, so an answer is accepted on the
    // strength of where it came from.
    dnssec-validation no;
    // Every question this resolver sends and every answer it accepts is written
    // to the log, which is what makes the walk down the tree readable after the
    // fact rather than only while dig is printing it.
    querylog yes;
};

logging {
    channel lab_log {
        file "/var/log/named.log" versions 3 size 5m;
        severity info;
        print-time yes;
        print-category yes;
    };
    category default   { lab_log; };
    category general   { lab_log; };
    category queries   { lab_log; };
    category resolver  { lab_log; };
};

// The root, as a set of hints rather than as a zone. A hint is a starting
// address, not authoritative data: the resolver asks the server named here for
// the root's real name-server set and uses that from then on.
zone "." {
    type hint;
    file "/var/bind/root.hints";
};
CONF

pkill -x named 2>/dev/null || true
sleep 1
named -c /etc/bind/named.conf

# Point this machine's own name resolution at the resolver it is running, so a
# curl or a ping by name here goes through the chain the lab is building.
cat > /etc/resolv.conf <<'RESOLV'
nameserver 127.0.0.1
options timeout:2 attempts:1
RESOLV

echo "client: recursive resolver on 115.0.0.40, root hints only"
