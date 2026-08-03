#!/bin/bash
# AS2 -- transit. The victim's only neighbour, so it always holds the legitimate
# route (direct, AS-path length 1) and is the frontier the equal-length hijack
# never crosses. Three eBGP sessions: AS1 (the victim), AS3, AS4. Addresses are
# the source of truth in scripts/lib.sh.
set -e
cat > /tmp/frr.conf <<'EOF'
interface host
 ip address 2.0.0.254/24
exit
interface to_as1
 ip address 10.0.12.2/30
exit
interface to_as3
 ip address 10.0.23.1/30
exit
interface to_as4
 ip address 10.0.24.1/30
exit
!
ip route 2.0.0.0/24 Null0
ip prefix-list OWN_PREFIX seq 5 permit 2.0.0.0/24
route-map ALLOW permit 10
exit
!
router bgp 2
 bgp router-id 2.2.2.2
 neighbor 10.0.12.1 remote-as 1
 neighbor 10.0.23.2 remote-as 3
 neighbor 10.0.24.2 remote-as 4
 address-family ipv4 unicast
  network 2.0.0.0/24
  neighbor 10.0.12.1 route-map ALLOW in
  neighbor 10.0.12.1 route-map ALLOW out
  neighbor 10.0.23.2 route-map ALLOW in
  neighbor 10.0.23.2 route-map ALLOW out
  neighbor 10.0.24.2 route-map ALLOW in
  neighbor 10.0.24.2 route-map ALLOW out
 exit-address-family
exit
EOF
vtysh -f /tmp/frr.conf
echo "AS2 up: transit, peering AS1 (victim), AS3, AS4"
