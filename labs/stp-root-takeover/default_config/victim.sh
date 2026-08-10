#!/bin/bash
# Starter config for the victim: an ordinary host behind S2 that talks to the
# gateway. It has no idea which physical path its frames take, which is the point
# of the lab: the spanning tree decides that, and the attacker attacks the tree.
ip addr flush dev 105-S2 2>/dev/null
ip addr add 105.0.0.20/24 dev 105-S2
ip link set 105-S2 up
echo "victim: 105.0.0.20/24 on 105-S2"
