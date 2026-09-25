#!/bin/sh
# Starter config for the console: the machine every stage is driven from.
#
# It starts nothing and serves nothing. Its whole job is to be somewhere the
# learner can reach all four sources from with one loop, which is what "four
# machines acting on one order" looks like when the population already exists.
# How a population comes to exist is the botnet lab's subject and not this one's;
# there is no payload here and nothing is recruited.
set -eu

C2_IP="129.2.0.10"
PREFIXLEN=24
OP_IF="129-S3"
GW="129.2.0.1"

ip addr replace "${C2_IP}/${PREFIXLEN}" dev "$OP_IF"
ip link set "$OP_IF" up
ip route replace default via "$GW"

echo "c2: ${C2_IP} up. The four sources are 129.1.0.42, .13, .68 and .27"
