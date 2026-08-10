#!/bin/bash
# Attacker starter config - pre-armed (the attacker side boots ready). It sits
# outside the network it surveys, at 104.0.0.10, with the router as its default
# gateway. It is given the target range and nothing else: no host list, no port
# list, no credentials.
#
# The image already carries the kit, all of it stock: zmap and masscan (sweep a
# range fast), nmap and its script library (identify what is behind a port),
# hydra plus a fifty-word password list (guess a login), and curl, ncat, telnet
# and tcpdump to confirm by hand what a scanner reported. No attack runs at
# spawn; the handout starts each step by hand.
set -e

ip address add 104.0.0.10/24 dev 104-ext 2>/dev/null || true
ip link set 104-ext up
ip route add default via 104.0.0.1 2>/dev/null || true

# A working directory for scan output, so the handout's redirections and the
# files it chains together land somewhere predictable.
mkdir -p /root/scan

# Tell zmap its interface and next-hop MAC up front.
#
# zmap builds raw Ethernet frames, so it needs the gateway's hardware address
# before it can send anything. Left to work it out itself on this link it hangs
# indefinitely after logging "found gateway IP 104.0.0.1", and it does so even
# when the kernel's own neighbour entry for the gateway is present and REACHABLE.
# Passing -G on the command line fixes it, but that would put an argument in every
# zmap command in the handout that exists only to work around the lab's own
# plumbing. Writing the same two values into zmap's config file instead lets the
# handout run zmap the way its documentation says to.
ping -c 1 -W 2 104.0.0.1 >/dev/null 2>&1 || true
GW_MAC="$( ip neigh show 104.0.0.1 | awk '{print $5}' | head -1 )"
if [ -n "$GW_MAC" ]; then
    sed -i '/^interface /d;/^gateway-mac /d' /etc/zmap/zmap.conf
    printf 'interface "104-ext"\ngateway-mac "%s"\n' "$GW_MAC" >> /etc/zmap/zmap.conf
else
    echo "warning: could not learn the gateway MAC; zmap will need -G" >&2
fi

echo "attacker armed at 104.0.0.10 (zmap, masscan, nmap, hydra available)"
