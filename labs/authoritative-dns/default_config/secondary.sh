#!/bin/sh
# Starter config: ns2.uni.lab, the machine that will hold a copy of the forward
# zone rather than the original.
#
# It arrives exactly as the primary does: named running, /etc/bind/named.conf
# given, /etc/bind/zones.conf empty. The parent zone above uni.lab already
# publishes this machine as one of the zone's two name servers, so the rest of
# the network has been told to ask it since the moment the lab was spawned. It
# answers REFUSED until Part 2 gives it the zone.
#
# /var/bind/secondary is where a transferred copy is written. named creates the
# file itself, so what has to exist beforehand is the directory, which the image
# provides.
set -e

ip addr replace 115.0.0.20/24 dev 115-S1
ip -6 addr replace fd00:115::20/64 dev 115-S1
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

echo "secondary: named running on 115.0.0.20 with no zones"
