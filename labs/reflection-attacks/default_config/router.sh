#!/bin/bash
# Edge-router starter config. This is the device the learner hardens: it forwards
# between the customer edge (cust, 102.0.0.0/24) and the core (core, 102.1.0.0/24),
# and it is where source-address verification belongs.
#
# It arrives with the gap to close. Forwarding is on and reverse-path filtering is
# OFF, so a forged source crosses it freely — that is the baseline the attack
# exploits. The container runs privileged, so /proc/sys/net is writable and the
# learner can turn on uRPF (rp_filter) or install an nftables ACL at runtime; see
# solution/ for the two reference fixes.
set -e

ip address add 102.0.0.1/24 dev cust
ip address add 102.1.0.1/24 dev core
ip link set cust up
ip link set core up

# Forward between the two subnets.
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Reverse-path filtering OFF everywhere: the router accepts a packet on cust no
# matter what source it claims. This is the missing defence, not a mistake to
# leave — the handout has the learner turn it on.
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.cust.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.core.rp_filter=0 >/dev/null

# No ACL: clear any nftables policy a previous run left behind, so the baseline is
# always "everything forwards".
nft delete table ip bcp38 2>/dev/null || true

echo "router up: forwarding cust(102.0.0.1) <-> core(102.1.0.1), no source filtering"
