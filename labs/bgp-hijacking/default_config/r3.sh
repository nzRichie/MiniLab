#!/bin/bash
# AS3 -- transit, one of the contested pair. Reaches the victim via AS2 (path
# 2 1, length 2) and the attacker via AS5 (path 5 6, length 2), so it is equidistant
# from both and every equal-length contest here is settled by a tie-break rather
# than by path length. A more-specific announcement overrides all of that by
# longest-prefix-match. Two eBGP sessions: AS2 and AS5.
#
# AS3 is also a BYSTANDER THAT VALIDATES. It has a link to the RPKI validator and
# Part 2 has the learner point it at that cache, but AS3 never acts on the verdict:
# it is where the learner sees routes marked Invalid and still chosen as best,
# which is the difference between validating and enforcing. Addresses are the
# source of truth in scripts/lib.sh.
set -e
cat > /tmp/frr.conf <<'EOF'
interface host
 ip address 3.0.0.254/24
exit
interface to_as2
 ip address 10.0.23.2/30
exit
interface to_as5
 ip address 10.0.35.1/30
exit
! Link to the RPKI validator. Carries RTR only; it is never announced into BGP.
interface to_rpki
 ip address 172.28.3.2/30
exit
!
ip route 3.0.0.0/24 Null0
ip prefix-list OWN_PREFIX seq 5 permit 3.0.0.0/24
route-map ALLOW permit 10
exit
!
router bgp 3
 bgp router-id 3.3.3.3
 neighbor 10.0.23.1 remote-as 2
 neighbor 10.0.35.2 remote-as 5
 address-family ipv4 unicast
  network 3.0.0.0/24
  neighbor 10.0.23.1 route-map ALLOW in
  neighbor 10.0.23.1 route-map ALLOW out
  neighbor 10.0.35.2 route-map ALLOW in
  neighbor 10.0.35.2 route-map ALLOW out
 exit-address-family
exit
EOF
vtysh -f /tmp/frr.conf
echo "AS3 up: transit, peering AS2, AS5"
