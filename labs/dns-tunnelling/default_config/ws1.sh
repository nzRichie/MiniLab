#!/bin/sh
# Starter config for ws1: the compromised workstation, and the machine the
# learner works from in Part 1.
#
# It is an ordinary inside host: an address, a default route through the gateway,
# and the resolver set as its nameserver, so `dig a-name` goes to the resolver
# while `dig @<outside-address> a-name` goes straight out. The one thing that
# makes it the machine the file leaves from is that the file is here, in
# /root/records/customer-records.csv. Nothing on this host sends it: the learner
# does, by hand, in Part 1.
#
# It is idempotent: reset.sh re-runs it, and it rewrites the file each time so a
# learner who moved it and then reset gets the same bytes back.
set -eu

PREFIXLEN=24
WS1_IP="119.0.0.23"
GW_INSIDE_IP="119.0.0.1"
RESOLVER_IP="119.0.0.2"
LAN_IF="119-lan"

ip addr replace "${WS1_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up
ip route replace default via "$GW_INSIDE_IP"

# The resolver is this host's nameserver, so a bare `dig name` uses it. A query
# aimed straight at an outside address with `dig @address` does not.
printf 'nameserver %s\n' "$RESOLVER_IP" > /etc/resolv.conf

# The file the exercise moves out. Small on purpose: a learner encodes it by hand
# and sends it as a handful of queries in Part 1, so it has to be a few lines,
# not a disk image. It is rewritten every run so its byte count is fixed and the
# answer key can name it.
mkdir -p /root/records
chmod 755 /root/records
cat > /root/records/customer-records.csv <<'EOF'
id,name,plan,secret_token
1001,A. Okonkwo,gold,7F3A9C2E
1002,B. Nakamura,silver,1D8B4655
1003,C. Petrova,gold,E29017AB
EOF
chmod 644 /root/records/customer-records.csv

echo "ws1: addressed ${WS1_IP}, resolver ${RESOLVER_IP}, records file in /root/records"
