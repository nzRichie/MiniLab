#!/bin/bash
# AS1 -- the VICTIM. Holder of 1.0.0.0/22, the block AS6 hijacks, and origin of the
# single aggregate announcement that covers it. One eBGP session, to AS2 (its only
# link to the rest of the topology). Every address here is the source of truth in
# scripts/lib.sh; this file is the in-container copy the router applies over vtysh,
# so the router is a pure control-plane device.
#
# The service lives on the first /24 of the block (1.0.0.1, on the connected
# 1.0.0.0/24 host link). The other three /24s of the allocation are unpopulated,
# which is normal: an operator announces the aggregate it was allocated, not the
# part it happens to have filled. Part 2 has the learner split this aggregate into
# /23s and then /24s, so only the /22 is announced here.
set -e
cat > /tmp/frr.conf <<'EOF'
interface host
 ip address 1.0.0.254/24
exit
interface to_as2
 ip address 10.0.12.1/30
exit
!
! Origination scaffold (mini-internet practice): a discard route so `network`
! always has a matching entry, plus OWN_PREFIX naming this AS's own block.
ip route 1.0.0.0/22 Null0
ip prefix-list OWN_PREFIX seq 5 permit 1.0.0.0/22 le 24
!
! FRR 9.1 enforces `bgp ebgp-requires-policy`: every neighbour needs inbound and
! outbound policy or it exchanges nothing. ALLOW is an empty permit -- it meets
! that requirement and leaves best-path selection to plain shortest-AS-path (no
! local-preference games), so a hijack's reach is decided only by prefix length
! and AS-path distance.
route-map ALLOW permit 10
exit
!
router bgp 1
 bgp router-id 1.1.1.1
 neighbor 10.0.12.2 remote-as 2
 address-family ipv4 unicast
  network 1.0.0.0/22
  neighbor 10.0.12.2 route-map ALLOW in
  neighbor 10.0.12.2 route-map ALLOW out
 exit-address-family
exit
EOF
vtysh -f /tmp/frr.conf
echo "AS1 (victim) up: originating 1.0.0.0/22, peering AS2"
