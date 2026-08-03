#!/bin/bash
# Generic host addressing for the BGP lab. Hosts are the bash side of the lab: the
# routers stay pure vtysh, and every host command (curl, traceroute, the identity
# banner) runs here. Args, all from scripts/lib.sh:
#   $1  primary address with prefix length (e.g. 2.0.0.100/24)
#   $2  default gateway (the router's host-facing address)
#   $3  optional secondary address (the AS6 attacker's 1.0.0.1/25 impostor IP)
# The banner server itself is started separately by spawn.sh with `docker exec -d`
# so it survives as a detached process.
set -e
ip_primary="$1"; gw="$2"; secondary="${3:-}"

ip address replace "$ip_primary" dev uplink
[ -n "$secondary" ] && ip address replace "$secondary" dev uplink
ip link set uplink up
ip route replace default via "$gw"

echo "host up: ${ip_primary}${secondary:+ (+${secondary})} gw ${gw}"
