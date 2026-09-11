#!/bin/sh
# Starter config for collector: the operator's authoritative server on the
# outside, and the machine that reassembles the file from the query names it is
# asked to resolve.
#
# It runs named, authoritative for evil.lab. A wildcard under t.evil.lab answers
# every data query with this host's address, so that a resolver recursing on the
# operator's behalf gets an answer and the query is a normal, completed lookup
# rather than a timeout. named writes every query it receives to a log; the
# decoder alongside it reads that log, pulls the data out of the names, and
# writes the running byte count the lab's oracle reads.
#
# INSTRUCTOR NOTE. This host's address is the destination the whole channel
# depends on, and the figure and status.sh do not name it. A learner who reads
# this file on the gateway learns the zone and the paths, which is why nothing
# here holds the workstation's file or says which workstation sends it.
#
# It is idempotent: reset.sh re-runs it, and it truncates every record so a fresh
# run starts from an empty count.
set -eu

PREFIXLEN=24
COLLECTOR_IP="119.1.0.66"
GW_OUTSIDE_IP="119.1.0.1"
EXT_IF="119-ext"

TUNNEL_DIR="/var/log/tunnel"
QUERYLOG="${TUNNEL_DIR}/queries.log"
RECEIVED="${TUNNEL_DIR}/received.log"

ip addr replace "${COLLECTOR_IP}/${PREFIXLEN}" dev "$EXT_IF"
ip link set "$EXT_IF" up
ip route replace default via "$GW_OUTSIDE_IP"

mkdir -p /var/bind /var/run/named "$TUNNEL_DIR"
chmod 755 /var/bind /var/run/named "$TUNNEL_DIR"

cat > /var/bind/evil.lab.db <<EOF
\$TTL 5
@    IN SOA ns.evil.lab. admin.evil.lab. ( 1 3600 600 86400 5 )
@    IN NS  ns.evil.lab.
ns   IN A   ${COLLECTOR_IP}
; Every data name has the shape <chunk>.<seq>.t.evil.lab. t.evil.lab is the
; closest existing node, so this wildcard synthesises an answer for all of them
; (RFC 4592): the lookup completes and the query is logged.
*.t  IN A   ${COLLECTOR_IP}
EOF

cat > /etc/bind/named.conf <<CONF
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    recursion no;
    minimal-responses yes;
    querylog yes;
};

logging {
    channel qlog {
        file "${QUERYLOG}" versions 3 size 20m;
        print-time yes;
        severity info;
    };
    category queries { qlog; };
    category default { qlog; };
};

zone "evil.lab" { type master; file "/var/bind/evil.lab.db"; };
CONF

# Start from empty records so Status counts this run only.
: > "$QUERYLOG"
rm -f "$RECEIVED" "$TUNNEL_DIR"/*.bin "$TUNNEL_DIR"/*.b32 2>/dev/null || true

pkill -x named 2>/dev/null || true
sleep 1
named -c /etc/bind/named.conf

# The decoder. It follows the query log, pulls the data labels out of the names
# ending in t.evil.lab, reassembles each source's file and appends one line per
# arrival to the record. It holds no address: the suffix and the paths are given
# here, from this lab's lib.sh values.
pkill -f '[t]unnel-decode\.py' 2>/dev/null || true
setsid python3 /usr/local/lib/minilabs/tunnel-decode.py \
    --suffix t.evil.lab \
    --querylog "$QUERYLOG" \
    --log "$RECEIVED" \
    --dir "$TUNNEL_DIR" >/dev/null 2>&1 &

echo "collector: authoritative for evil.lab on ${COLLECTOR_IP}:53, decoder following ${QUERYLOG}"
