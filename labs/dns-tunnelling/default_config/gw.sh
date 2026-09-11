#!/bin/sh
# Starter config for gw: the gateway, and the machine Part 2A is worked from.
#
# It arrives with two addressed interfaces, forwarding on, and a starter egress
# policy that already blocks general outbound and permits only DNS. That policy
# is the environment the channel exploits: an inside host cannot open a plain
# connection to the outside, so a request to pub's web banner is dropped, but a
# DNS query to anywhere on port 53 is allowed out, because name resolution is
# treated as essential. Part 2A narrows that DNS permission to the resolver
# alone.
#
# net.ipv4.ip_forward is set at container creation rather than here, because
# Docker mounts /proc/sys read-only in an unprivileged container.
#
# There is no address translation, and that is a decision rather than an
# omission. Without NAT, every query crossing the gateway carries the inside
# host's own address, so a capture here and the collector's own record both say
# which inside host each query came from.
#
# It is idempotent, and reset.sh re-runs it to throw away the learner's Part 2A
# changes and restore the starter policy.
set -eu

PREFIXLEN=24
GW_INSIDE_IP="119.0.0.1"
GW_OUTSIDE_IP="119.1.0.1"
GW_INSIDE_IF="lan"
GW_OUTSIDE_IF="ext"
INSIDE_SUBNET="119.0.0.0/24"
DNS_PORT=53

NFT_TABLE="egress"

ip addr replace "${GW_INSIDE_IP}/${PREFIXLEN}" dev "$GW_INSIDE_IF"
ip addr replace "${GW_OUTSIDE_IP}/${PREFIXLEN}" dev "$GW_OUTSIDE_IF"
ip link set "$GW_INSIDE_IF" up
ip link set "$GW_OUTSIDE_IF" up

# Rebuild the starter policy from scratch, so a reset throws away whatever the
# learner wrote in Part 2A and restores exactly this.
nft delete table inet "$NFT_TABLE" 2>/dev/null || true
nft -f - <<NFT
table inet ${NFT_TABLE} {
    chain ${NFT_TABLE}_forward {
        type filter hook forward priority filter; policy drop;

        # The replies to anything already allowed out come back on this hook too.
        ct state established,related accept

        # DNS is the one thing this network lets out. Any inside host may send a
        # query to any outside address on udp or tcp port 53. This is the hole
        # the channel uses, and the rule Part 2A rewrites so that only the
        # resolver keeps it.
        iifname "${GW_INSIDE_IF}" ip daddr != ${INSIDE_SUBNET} udp dport ${DNS_PORT} accept
        iifname "${GW_INSIDE_IF}" ip daddr != ${INSIDE_SUBNET} tcp dport ${DNS_PORT} accept

        # Everything else forwarded between the two segments is dropped by the
        # chain's policy: a plain connection from an inside host to a web service
        # on the outside never completes, which is why DNS is the way out.
    }
}
NFT

rm -f /tmp/egress.pcap

echo "gw: addressed ${GW_INSIDE_IP} inside and ${GW_OUTSIDE_IP} outside, forwarding, DNS-only egress"
