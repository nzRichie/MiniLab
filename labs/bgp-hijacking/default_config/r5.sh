#!/bin/bash
# AS5 -- transit, and the DEFENDER. It is the attacker's only upstream, so every
# route AS6 injects crosses this router, which makes it the one place a policy can
# stop all of them. It is also the AS the attacker wins outright at any equal
# prefix length: its path to AS6 is length 1 while its legitimate path to the
# victim is length 3. That is why AS5 is still captured after both sides have
# deaggregated to the /24 floor, and why Part 2 ends here.
#
# Three eBGP sessions: AS3, AS4, AS6 (the attacker). AS5 also has a link to the
# RPKI validator; Part 2 has the learner configure the cache and then the import
# policy that drops RPKI-Invalid routes. Addresses live in scripts/lib.sh.
set -e
cat > /tmp/frr.conf <<'EOF'
interface host
 ip address 5.0.0.254/24
exit
interface to_as3
 ip address 10.0.35.2/30
exit
interface to_as4
 ip address 10.0.45.2/30
exit
interface to_as6
 ip address 10.0.56.1/30
exit
! Link to the RPKI validator. Carries RTR only; it is never announced into BGP.
interface to_rpki
 ip address 172.28.5.2/30
exit
!
ip route 5.0.0.0/24 Null0
ip prefix-list OWN_PREFIX seq 5 permit 5.0.0.0/24
route-map ALLOW permit 10
exit
!
router bgp 5
 bgp router-id 5.5.5.5
 neighbor 10.0.35.1 remote-as 3
 neighbor 10.0.45.1 remote-as 4
 neighbor 10.0.56.2 remote-as 6
 address-family ipv4 unicast
  network 5.0.0.0/24
  neighbor 10.0.35.1 route-map ALLOW in
  neighbor 10.0.35.1 route-map ALLOW out
  neighbor 10.0.45.1 route-map ALLOW in
  neighbor 10.0.45.1 route-map ALLOW out
  neighbor 10.0.56.2 route-map ALLOW in
  neighbor 10.0.56.2 route-map ALLOW out
 exit-address-family
exit
EOF
vtysh -f /tmp/frr.conf
echo "AS5 (defender) up: transit, peering AS3, AS4, AS6 (attacker)"
