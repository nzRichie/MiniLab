#!/bin/sh
# Starter config: the root server, and everything above uni.lab.
#
# This machine is given whole and the learner never edits it. It holds the three
# zones that sit between the root and the zone the learner authors, so the client
# resolves by walking down a real delegation chain instead of being pointed
# straight at one server:
#
#   .      delegates lab.                    to this machine
#   lab.   delegates uni.lab.                to ns1.uni.lab and ns2.uni.lab
#   arpa.  delegates 0.0.115.in-addr.arpa.   to ns1.uni.lab
#
# The two delegations in lab. and arpa. are also this lab's worked examples of
# the rule the learner applies in Part 3. lab. must carry address records for
# ns1.uni.lab and ns2.uni.lab, because those names are inside the zone being
# delegated and nothing could look them up otherwise. arpa. carries no address
# record for ns1.uni.lab, because from arpa. that name is reachable through a
# different branch of the tree.
#
# The root server's own name is ns.root-lab. rather than something under lab.
# The root zone delegates lab. away, so a name under lab. would sit below a zone
# cut and could only appear in the root zone as glue; root-lab. is delegated
# nowhere, so the root zone holds its address as ordinary authoritative data.
set -e

ip addr replace 115.0.0.2/24 dev 115-S1
ip -6 addr replace fd00:115::2/64 dev 115-S1
ip link set 115-S1 up

mkdir -p /var/bind /var/run/named
chmod 755 /var/bind /var/run/named

# --- the root zone --------------------------------------------------------
cat > /var/bind/root.zone <<'ZONE'
$TTL 86400
.               IN  SOA ns.root-lab. hostmaster.root-lab. (
                        2026083101  ; serial
                        3600        ; refresh
                        600         ; retry
                        1209600     ; expire
                        3600 )      ; negative caching TTL
.               IN  NS  ns.root-lab.
ns.root-lab.    IN  A       115.0.0.2
ns.root-lab.    IN  AAAA    fd00:115::2
; Two delegations. Neither needs an address record here: ns.root-lab. is not
; inside lab. and not inside arpa., so a resolver that has the root zone's own
; data already knows where to send the next query.
lab.            IN  NS  ns.root-lab.
arpa.           IN  NS  ns.root-lab.
ZONE

# --- the lab. TLD ---------------------------------------------------------
cat > /var/bind/lab.zone <<'ZONE'
$TTL 86400
@               IN  SOA ns.root-lab. hostmaster.root-lab. (
                        2026083101  ; serial
                        3600        ; refresh
                        600         ; retry
                        1209600     ; expire
                        3600 )      ; negative caching TTL
@               IN  NS  ns.root-lab.
; The delegation of uni.lab, published here by the parent and not by the child.
; Both name-server names are inside the zone being delegated, so both need an
; address record in this file: a resolver holding only this zone would otherwise
; have to ask uni.lab where uni.lab's servers are.
uni             IN  NS  ns1.uni.lab.
uni             IN  NS  ns2.uni.lab.
ns1.uni         IN  A   115.0.0.10
ns2.uni         IN  A   115.0.0.20
ZONE

# --- the arpa. branch -----------------------------------------------------
cat > /var/bind/arpa.zone <<'ZONE'
$TTL 86400
@                       IN  SOA ns.root-lab. hostmaster.root-lab. (
                                2026083101  ; serial
                                3600        ; refresh
                                600         ; retry
                                1209600     ; expire
                                3600 )      ; negative caching TTL
@                       IN  NS  ns.root-lab.
; The reverse /24 is delegated to the same machine that holds the forward zone.
; ns1.uni.lab. is not inside 0.0.115.in-addr.arpa., so no address record belongs
; here: a resolver follows the lab. branch to find it.
0.0.115.in-addr         IN  NS  ns1.uni.lab.
ZONE

cat > /etc/bind/named.conf <<'CONF'
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    allow-query { any; };
    // Authoritative only. A server that answers for a zone it holds and refuses
    // everything else is what every server above uni.lab in the real tree does.
    recursion no;
    // Nothing in this lab is signed, so there is nothing to validate and no
    // trust anchor to load. Saying so stops named priming itself against root
    // servers this network does not have.
    dnssec-validation no;
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

zone "." {
    type primary;
    file "/var/bind/root.zone";
};

zone "lab" {
    type primary;
    file "/var/bind/lab.zone";
};

zone "arpa" {
    type primary;
    file "/var/bind/arpa.zone";
};
CONF

pkill -x named 2>/dev/null || true
sleep 1
named -c /etc/bind/named.conf

echo "root: authoritative for . , lab. and arpa. on 115.0.0.2"
