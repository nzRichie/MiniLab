#!/bin/sh
# Starter config: ns1.cs.uni.lab, the only server for the child zone.
#
# It arrives exactly as the other two do: named running, /etc/bind/named.conf
# given, /etc/bind/zones.conf empty. Nothing above it points here yet. The parent
# zone gains that pointer in Part 3, and it is the learner who writes it, on the
# primary, at the same time as they write the child zone here.
#
# The web server is given, and it is what makes the delegation visible as
# something other than a DNS answer: a name in the child zone, resolved from the
# root by a client that was never told this machine exists, reaching this
# machine.
set -e

ip addr replace 115.0.0.30/24 dev 115-S1
ip -6 addr replace fd00:115::30/64 dev 115-S1
ip link set 115-S1 up

mkdir -p /var/bind /var/run/named
chmod 755 /var/bind /var/run/named

# The learner's file. It is included from named.conf below, and it starts empty.
cat > /etc/bind/zones.conf <<'CONF'
// Zone statements for this server. Nothing is declared yet.
//
// A zone this server holds needs two things: a statement here that names the
// zone and the file its records are in, and that file under /var/bind. Writing
// one without the other leaves named either holding no zone or refusing to
// start.
CONF

cat > /etc/bind/named.conf <<'CONF'
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    allow-query { any; };
    // Authoritative only. This server answers for the zones it holds and
    // refuses everything else; it never goes and looks a name up elsewhere.
    recursion no;
    // Nothing in this lab is signed, so there is nothing to validate.
    dnssec-validation no;
};

// The shared secret rndc authenticates with. It has to be included before the
// controls block below names it, or named refuses to start with "unknown key".
include "/etc/bind/rndc.key";

// rndc connects here. `rndc reload` and `rndc zonestatus` are how a running
// named is told to re-read a zone file and asked what it currently holds,
// without stopping it.
controls {
    inet 127.0.0.1 port 953 allow { 127.0.0.1; } keys { "rndc-key"; };
};

logging {
    channel lab_log {
        file "/var/log/named.log" versions 3 size 5m;
        severity info;
        print-time yes;
        print-category yes;
    };
    category default  { lab_log; };
    category general  { lab_log; };
    category notify   { lab_log; };
    category xfer-in  { lab_log; };
    category xfer-out { lab_log; };
};

include "/etc/bind/zones.conf";
CONF

pkill -x named 2>/dev/null || true
sleep 1
named -c /etc/bind/named.conf

# The machine behind www.cs.uni.lab. It answers on port 80 over IPv4 and IPv6
# alike, so whichever address record a client uses reaches the same page.
#
# The pattern pkill is given is the identity string, not the script name.
# banner-server execs python3, which replaces the shell's argv with python's, so
# `pkill -f banner-server` matches nothing at all and a second copy would then
# fail to bind the port with no message anybody sees. The identity string is
# python3's last argument, so it is in the argv that is actually there.
pkill -f 'CS-DEPT-9F03A6' 2>/dev/null || true
sleep 1
nohup /usr/local/bin/banner-server 'CS-DEPT-9F03A6' >/dev/null 2>&1 &

echo "sub: named running on 115.0.0.30 with no zones; web page on port 80"
