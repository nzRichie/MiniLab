#!/bin/sh
# Starter config: the caching resolver the campus uses, and the machine the whole
# lab is about.
#
# It arrives configured the way a resolver was configured before source-port
# randomisation was deployed in 2008, and the three lines that make it so are in
# a file of their own, /etc/bind/hardening.conf, because Part 2 rewrites them:
#
#   query-source ... port 33333   every outgoing query leaves from the same port,
#                                 so an off-path attacker has only the 16-bit
#                                 transaction ID left to guess
#   allow-recursion { any; }      anybody who can reach this resolver, from any
#                                 network, can make it look a name up
#   dnssec-validation no          signatures on a signed zone are not checked
#
# /etc/bind/trust-anchors.conf is included by named.conf and starts empty. The
# key it will hold is written to /etc/bind/uni.lab.key by spawn.sh, which reads
# it off the authoritative server, standing in for the zone operator publishing
# its public key. Installing it is Part 2's work.
#
# The resolver is told where uni.lab and attack.lab live with a static delegation
# rather than by walking down from the root, because this lab has no root zone.
# What matters for the attack is unchanged: the resolver still sends a query of
# its own to the authoritative server and still has to decide whether the answer
# that comes back is the one it asked for.
set -e

ip addr replace 107.1.0.10/24 dev 107-S1
ip link set 107-S1 up
ip route replace default via 107.1.0.1

mkdir -p /var/bind /var/run/named
chmod 755 /var/bind /var/run/named

cat > /etc/bind/hardening.conf <<'CONF'
// The three settings this lab turns on and off. They start weak; Part 2 of the
// handout is where they are rewritten. Included from inside the options block of
// /etc/bind/named.conf.
query-source address * port 33333;
allow-recursion { any; };
dnssec-validation no;
CONF

: > /etc/bind/trust-anchors.conf
cat > /etc/bind/trust-anchors.conf <<'CONF'
// No trust anchor is installed. With none configured, a resolver has no key to
// start a validation chain from, so there is nothing for dnssec-validation to
// check even when it is switched on.
CONF

cat > /etc/bind/named.conf <<'CONF'
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    recursion yes;
    max-cache-ttl 604800;
    // DNS cookies (RFC 7873) would give this resolver a value only the real
    // server could return, which an off-path attacker cannot forge. They are off
    // so an answer is matched on address, port and transaction ID alone, which
    // is what a resolver had before the mechanism existed.
    send-cookie no;
    querylog yes;
    include "/etc/bind/hardening.conf";
};

include "/etc/bind/trust-anchors.conf";

zone "uni.lab"    { type static-stub; server-addresses { 107.2.0.10; }; };
zone "attack.lab" { type static-stub; server-addresses { 107.3.0.10; }; };
CONF

pkill -x named 2>/dev/null || true
sleep 1
named -c /etc/bind/named.conf

echo "resolver: caching resolver on 107.1.0.10:53, outgoing queries pinned to port 33333"
