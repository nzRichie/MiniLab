#!/bin/sh
# Starter config: the attacker, on its own link and on the path of nothing.
#
# It arrives with two things already running and nothing else:
#   named          authoritative for attack.lab, answering every name in it with
#                  this machine's own address. Its purpose is to be a zone the
#                  resolver will look a name up in on demand, so that the
#                  resolver's outgoing query lands on this interface where it can
#                  be read.
#   banner-server  the impostor's HTTP identity on port 80, so a poisoned lookup
#                  is visible as a different machine answering.
#
# The spoofer itself is not started. dns-spoof is on the path and takes no
# default addresses, ports or names: aiming it is Part 1's work.
set -e

ip addr replace 107.3.0.10/24 dev 107-ext
ip link set 107-ext up
ip route replace default via 107.3.0.1

mkdir -p /var/bind
chmod 755 /var/bind

cat > /var/bind/attack.lab.zone <<'ZONE'
$TTL 30
@       IN  SOA ns.attack.lab. root.attack.lab. (
                2026081301  ; serial
                3600        ; refresh
                900         ; retry
                604800      ; expire
                30 )        ; negative caching TTL
        IN  NS  ns.attack.lab.
ns      IN  A   107.3.0.10
*       IN  A   107.3.0.10
ZONE

cat > /etc/bind/named.conf <<'CONF'
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    recursion no;
    dnssec-validation no;
    answer-cookie no;
    querylog yes;
};

zone "attack.lab" {
    type primary;
    file "/var/bind/attack.lab.zone";
};
CONF

pkill -x named 2>/dev/null || true
pkill -f banner-server 2>/dev/null || true
pkill -f 'http.server' 2>/dev/null || true
pkill -x dns-spoof 2>/dev/null || true
pkill -f dns-spoof 2>/dev/null || true
sleep 1

named -c /etc/bind/named.conf

banner-server "IMPOSTOR: the attacker's host (107.3.0.10)" >/dev/null 2>&1 &

echo "attacker: attack.lab served on 107.3.0.10:53; dns-spoof is on the path, unaimed"
