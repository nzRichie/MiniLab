#!/bin/sh
# Starter config for resolver: the campus recursive resolver, and the machine the
# learner writes a response policy on in Part 2B.
#
# It resolves names for the inside network. It has no upstream forwarder: it
# recurses from a small root zone it serves itself, which delegates example.lab
# to the legitimate server and evil.lab to the operator's server, exactly as the
# real root delegates a registered domain to whoever registered it. There is no
# separate root container; this one file is the whole "internet" the resolver
# walks. That the operator's zone is reachable by ordinary recursion is the
# reason Part 2A's gateway rule cannot stop the channel once it moves onto this
# resolver, and Part 2B's response policy can.
#
# It arrives with NO response policy. /etc/bind/rpz-policy.conf (included inside
# the options block) and /etc/bind/rpz-zones.conf (included at the top level)
# both start empty; Part 2B fills them, and reset.sh empties them again.
#
# It is idempotent: reset.sh re-runs it.
set -eu

PREFIXLEN=24
RESOLVER_IP="119.0.0.2"
GW_INSIDE_IP="119.0.0.1"
LAN_IF="119-lan"
PUB_IP="119.1.0.10"
COLLECTOR_IP="119.1.0.66"

ip addr replace "${RESOLVER_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up
ip route replace default via "$GW_INSIDE_IP"

mkdir -p /var/bind /var/run/named
chmod 755 /var/bind /var/run/named

# The local root. Its own NS is this resolver; the two delegations point at the
# authoritative servers on the outside, with glue.
cat > /var/bind/root.db <<EOF
\$TTL 60
.               IN SOA a.root.lab. admin.root.lab. ( 1 3600 600 86400 60 )
.               IN NS  a.root.lab.
a.root.lab.     IN A   ${RESOLVER_IP}
example.lab.    IN NS  ns.example.lab.
ns.example.lab. IN A   ${PUB_IP}
evil.lab.       IN NS  ns.evil.lab.
ns.evil.lab.    IN A   ${COLLECTOR_IP}
EOF

# The two response-policy include files start empty. A comment rather than a
# truly empty file so named-checkconf and a reader both see why they exist.
cat > /etc/bind/rpz-policy.conf <<'EOF'
// Part 2B writes a response-policy statement here, naming the policy zone below.
// Empty at spawn: with no policy, the resolver recurses into every zone,
// evil.lab included.
EOF
cat > /etc/bind/rpz-zones.conf <<'EOF'
// Part 2B writes the policy zone here (a zone whose records name what to block
// and what to answer instead). Empty at spawn.
EOF

cat > /etc/bind/named.conf <<'CONF'
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    allow-recursion { any; };
    recursion yes;
    // The local root and both delegated zones are unsigned, so validation
    // against the built-in root trust anchor would fail every lookup. This lab
    // is not about DNSSEC; the cache-poisoning lab is.
    dnssec-validation no;
    // Send the full query name to each authoritative server rather than the
    // minimised prefix, so a data query reaches the collector as one lookup for
    // the whole name. The lab is not about qname minimisation.
    qname-minimization off;
    querylog yes;
    include "/etc/bind/rpz-policy.conf";
};

include "/etc/bind/rpz-zones.conf";

zone "." { type master; file "/var/bind/root.db"; };
CONF

pkill -x named 2>/dev/null || true
sleep 1
named -c /etc/bind/named.conf

echo "resolver: recursive on ${RESOLVER_IP}:53, local root delegating example.lab and evil.lab, no response policy"
