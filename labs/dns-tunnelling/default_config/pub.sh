#!/bin/sh
# Starter config for pub: the legitimate authoritative server on the outside.
#
# It is authoritative for example.lab, the ordinary external zone whose name the
# resolver must still be able to look up after the learner's defence is in place.
# www.example.lab resolving to this host, and a request to its web banner, are
# the two checks that Part 2 blocked the channel without blocking the internet.
#
# It is idempotent: reset.sh re-runs it.
set -eu

PREFIXLEN=24
PUB_IP="119.1.0.10"
GW_OUTSIDE_IP="119.1.0.1"
EXT_IF="119-ext"

ip addr replace "${PUB_IP}/${PREFIXLEN}" dev "$EXT_IF"
ip link set "$EXT_IF" up
ip route replace default via "$GW_OUTSIDE_IP"

mkdir -p /var/bind /var/run/named
chmod 755 /var/bind /var/run/named

cat > /var/bind/example.lab.db <<EOF
\$TTL 60
@   IN SOA ns.example.lab. admin.example.lab. ( 1 3600 600 86400 60 )
@   IN NS  ns.example.lab.
ns  IN A   ${PUB_IP}
@   IN A   ${PUB_IP}
www IN A   ${PUB_IP}
EOF

cat > /etc/bind/named.conf <<'CONF'
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    recursion no;
};

zone "example.lab" { type master; file "/var/bind/example.lab.db"; };
CONF

pkill -x named 2>/dev/null || true
sleep 1
named -c /etc/bind/named.conf

# The web banner, the thing the gateway refuses to let an inside host reach. It
# is bound to this host's one address so a request that does arrive is answered,
# which is what makes the difference between "blocked at the gateway" and "no
# such service" visible.
pkill -f '[w]eb-banner' 2>/dev/null || true
setsid web-banner "example.lab served by pub (${PUB_IP})" 80 >/dev/null 2>&1 &

echo "pub: authoritative for example.lab on ${PUB_IP}:53, web banner on :80"
