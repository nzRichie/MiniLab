#!/bin/sh
# Starter config: the campus host that asks the resolver and believes the answer.
#
# It runs no service and holds no defence. Its entire role is to be the machine
# whose lookup is wrong: `dig www.uni.lab` here reports whatever the resolver has
# cached, and `curl` says which machine that address actually belongs to.
set -e

ip addr replace 107.1.0.20/24 dev 107-S1
ip link set 107-S1 up
ip route replace default via 107.1.0.1

# The campus resolver, and nothing else. Docker writes its own resolv.conf into
# every container; this replaces it, so a bare `dig www.uni.lab` on this host goes
# to the resolver under attack rather than anywhere else.
cat > /etc/resolv.conf <<'CONF'
nameserver 107.1.0.10
options timeout:3 attempts:1
CONF

echo "victim: 107.1.0.20/24, resolver 107.1.0.10"
