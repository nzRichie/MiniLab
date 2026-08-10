#!/bin/bash
# Starter config for the gateway: the host behind S3 that the victim's traffic is
# aimed at. It is the far end of the path the attacker wants to sit on.
ip addr flush dev 105-S3 2>/dev/null
ip addr add 105.0.0.1/24 dev 105-S3
ip link set 105-S3 up
echo "gateway: 105.0.0.1/24 on 105-S3"
