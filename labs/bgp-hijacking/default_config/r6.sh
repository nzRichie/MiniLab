#!/bin/bash
# AS6 -- the ATTACKER. At baseline it is an ordinary AS: it originates only its own
# 6.0.0.0/24 and peers with its single upstream AS5. It does NOT announce the
# hijack here; the learner types that into vtysh at runtime, following the handout.
#
# The host interface carries a second address, 1.0.0.126/25 -- the gateway for the
# 1.0.0.0/25 slice of the victim's block that the attacker stands up locally. That
# connected /25 is what lets AS6, once it announces the hijack, forward the drawn
# traffic to the impostor host (1.0.0.1) instead of black-holing it. Addresses are
# the source of truth in scripts/lib.sh.
set -e
cat > /tmp/frr.conf <<'EOF'
interface host
 ip address 6.0.0.254/24
 ip address 1.0.0.126/25
exit
interface to_as5
 ip address 10.0.56.2/30
exit
!
ip route 6.0.0.0/24 Null0
ip prefix-list OWN_PREFIX seq 5 permit 6.0.0.0/24
route-map ALLOW permit 10
exit
!
router bgp 6
 bgp router-id 6.6.6.6
 neighbor 10.0.56.1 remote-as 5
 address-family ipv4 unicast
  network 6.0.0.0/24
  neighbor 10.0.56.1 route-map ALLOW in
  neighbor 10.0.56.1 route-map ALLOW out
 exit-address-family
exit
EOF
vtysh -f /tmp/frr.conf
echo "AS6 (attacker) up: originating 6.0.0.0/24, peering AS5; impostor /25 staged, not yet announced"
