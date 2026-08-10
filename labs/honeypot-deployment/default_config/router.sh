#!/bin/sh
# Starter config for the router: address all four segments and install the edge
# filter the site already had before anyone thought about honeypots.
#
# What this deliberately does NOT do is redirect anything, or say a word about
# what the honeypot segment may reach. Both are the learner's work: the redirect
# in Part 2, the containment in Part 3.
set -eu

AS=106
PREFIXLEN=24

EXT_SUBNET="106.0.0.0/24"
PROD_SUBNET="106.1.0.0/24"
HONEY_SUBNET="106.2.0.0/24"
MGMT_SUBNET="106.3.0.0/24"

ROUTER_EXT_IP="106.0.0.1"
ROUTER_PROD_IP="106.1.0.1"
ROUTER_HONEY_IP="106.2.0.1"
ROUTER_MGMT_IP="106.3.0.1"

PROD_IP="106.1.0.20"

# `addr replace` rather than `addr add`, and the nft table is dropped before it is
# rebuilt below, so this script is safe to run a second time. reset.sh re-runs it
# to rebuild the baseline, and an `add` would fail with EEXIST on the first line
# and leave the rest of the file unexecuted.
ip addr replace "${ROUTER_EXT_IP}/${PREFIXLEN}"   dev ext
ip addr replace "${ROUTER_PROD_IP}/${PREFIXLEN}"  dev prod
ip addr replace "${ROUTER_HONEY_IP}/${PREFIXLEN}" dev honey
ip addr replace "${ROUTER_MGMT_IP}/${PREFIXLEN}"  dev mgmt

ip link set ext   up
ip link set prod  up
ip link set honey up
ip link set mgmt  up

# The edge filter. The site's policy is that the outside world may reach exactly
# one service on the production host, its SSH port, and nothing else. That is why
# the attacker cannot simply fetch production's web service directly, and it is
# the whole of the site's network security before the learner arrives.
#
# The policy is written as accept-with-explicit-drops rather than a default deny,
# because it only constrains what arrives from the external segment: management
# traffic and anything the internal segments originate are untouched. That
# omission is the gap Part 3 is about, and it is a realistic one — an edge
# firewall is written against the outside and routinely says nothing at all about
# what the hosts behind it may reach.
#
# The conntrack rule comes first so replies to sessions the policy already
# allowed are never re-examined against the rules below it.
nft delete table inet edge 2>/dev/null || true
nft add table inet edge
nft "add chain inet edge forward { type filter hook forward priority filter ; policy accept ; }"
nft add rule inet edge forward ct state established,related accept
nft add rule inet edge forward ip saddr "$EXT_SUBNET" ip daddr "$PROD_IP" tcp dport 22 accept
nft add rule inet edge forward ip saddr "$EXT_SUBNET" ip daddr "$PROD_SUBNET" drop

echo "router: four segments addressed, edge filter loaded (external -> production:22 only)"
