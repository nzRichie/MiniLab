#!/bin/bash
# AS4 -- transit, the other contested router. Symmetric to AS3: victim via AS2
# (path 2 1, length 2), and under the equal-length hijack a tying path 5 6 via
# AS5 that loses the tie to the incumbent. Two eBGP sessions: AS2 and AS5.
# Addresses are the source of truth in scripts/lib.sh.
set -e
cat > /tmp/frr.conf <<'EOF'
interface host
 ip address 4.0.0.254/24
exit
interface to_as2
 ip address 10.0.24.2/30
exit
interface to_as5
 ip address 10.0.45.1/30
exit
!
ip route 4.0.0.0/24 Null0
ip prefix-list OWN_PREFIX seq 5 permit 4.0.0.0/24
route-map ALLOW permit 10
exit
!
router bgp 4
 bgp router-id 4.4.4.4
 neighbor 10.0.24.1 remote-as 2
 neighbor 10.0.45.2 remote-as 5
 address-family ipv4 unicast
  network 4.0.0.0/24
  neighbor 10.0.24.1 route-map ALLOW in
  neighbor 10.0.24.1 route-map ALLOW out
  neighbor 10.0.45.2 route-map ALLOW in
  neighbor 10.0.45.2 route-map ALLOW out
 exit-address-family
exit
EOF
vtysh -f /tmp/frr.conf
echo "AS4 up: transit, peering AS2, AS5"
