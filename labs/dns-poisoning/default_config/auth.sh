#!/bin/sh
# Starter config: the authoritative server for uni.lab, and the real host behind
# the name www.uni.lab.
#
# Three processes run here:
#   named        authoritative for uni.lab, on 127.0.0.1:5353 and nowhere else
#   slow-link    on 107.2.0.10:53, passing queries to named and holding each reply
#                back by 400 ms
#   banner-server the real host's HTTP identity on port 80
#
# named is deliberately not on the LAN address. Every query from the outside
# arrives at slow-link instead, so every answer carries the delay, and the source
# address a forged answer has to claim is 107.2.0.10:53 either way.
#
# The zone is signed from the moment it is served, whether or not anything is
# checking the signatures. That is the ordinary case on the real internet: a
# signed zone is published by its operator, and whether a signature is checked is
# a decision each resolver makes for itself. Part 2 of the handout is where the
# resolver starts checking.
set -e

ip addr replace 107.2.0.10/24 dev 107-ext
ip link set 107-ext up
ip route replace default via 107.2.0.1

mkdir -p /var/bind/keys
chmod 755 /var/bind /var/bind/keys

cat > /var/bind/uni.lab.zone <<'ZONE'
$TTL 60
@       IN  SOA ns.uni.lab. hostmaster.uni.lab. (
                2026081301  ; serial
                3600        ; refresh
                900         ; retry
                604800      ; expire
                60 )        ; negative caching TTL
        IN  NS  ns.uni.lab.
ns      IN  A   107.2.0.10
www     IN  A   107.2.0.10
ZONE

cat > /etc/bind/named.conf <<'CONF'
options {
    directory "/var/bind";
    key-directory "/var/bind/keys";
    pid-file "/var/run/named/named.pid";
    // Reachable only through slow-link, which relays from the LAN address.
    listen-on port 5353 { 127.0.0.1; };
    listen-on-v6 { none; };
    allow-query { any; };
    recursion no;
    // Nothing here validates anything: this server publishes signatures, it does
    // not check anybody else's. Saying so stops named loading the built-in root
    // trust anchor and trying to prime itself from the root servers, which this
    // lab has none of.
    dnssec-validation no;
    // DNS cookies (RFC 7873) would give the resolver a value only this server
    // could return, which an off-path attacker cannot forge. They are off so the
    // lab's answers are matched on address, port and transaction ID alone, which
    // is what resolvers and servers had before the mechanism existed.
    answer-cookie no;
};

zone "uni.lab" {
    type primary;
    file "/var/bind/uni.lab.zone";
    dnssec-policy "default";
    inline-signing yes;
};
CONF

pkill -x named 2>/dev/null || true
pkill -f slow-link 2>/dev/null || true
pkill -f banner-server 2>/dev/null || true
pkill -f 'http.server' 2>/dev/null || true
sleep 1

named -c /etc/bind/named.conf

# Wait for named to answer on loopback before putting the relay in front of it.
i=0
while [ "$i" -lt 40 ]; do
    if dig +short +timeout=1 +tries=1 @127.0.0.1 -p 5353 www.uni.lab A >/dev/null 2>&1; then
        break
    fi
    i=$(( i + 1 ))
    sleep 0.25
done

slow-link --listen 107.2.0.10 --port 53 \
          --upstream 127.0.0.1 --upstream-port 5353 \
          --delay-ms 400 >/var/log/slow-link.log 2>&1 &

banner-server "the real www.uni.lab (authoritative host, 107.2.0.10)" >/dev/null 2>&1 &

echo "auth: uni.lab served on 107.2.0.10:53, replies delayed by 400 ms"
