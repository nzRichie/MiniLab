#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline WITHOUT tearing it down: stop the
# flood and the rogue server, drop any switch defences the learner added, refill the
# real pool, and re-lease the victim from the honest server. A learner who broke the
# lab is back at the starting line.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping the flood and the rogue server on the attacker"
docker exec "$ATTACKER_CTN" pkill -f dhcp-starve 2>/dev/null || true
docker exec "$ATTACKER_CTN" pkill -f dhcpd       2>/dev/null || true

echo "[reset] removing any DHCP-snooping flows/meters (back to plain switching)"
docker exec "$SW_CTN" ovs-ofctl del-flows br0 2>/dev/null || true
docker exec "$SW_CTN" ovs-ofctl -O OpenFlow13 del-meters br0 2>/dev/null || true
# del-flows also wipes the implicit priority=0 NORMAL flow a standalone bridge uses
# to forward. With no controller to repopulate it, an empty table is a black hole:
# no DHCP, no ARP, nothing crosses the switch, so the victim below leases nothing.
# Re-add the NORMAL flow so the switch forwards like a plain L2 switch again, the
# same state it had at spawn.
docker exec "$SW_CTN" ovs-ofctl add-flow br0 "priority=0,actions=NORMAL" 2>/dev/null || true

echo "[reset] restarting the real server (refills the pool) and re-leasing the victim"
# Re-applying the configs restarts the legit dhcpd with an empty leases file
# (full pool) and drives the victim through a fresh DORA against it.
docker exec "$SERVER_CTN"   "/home/server.sh"   2>/dev/null || true
docker exec "$ATTACKER_CTN" "/home/attacker.sh" 2>/dev/null || true
docker exec "$VICTIM_CTN"   "/home/victim.sh"   2>/dev/null || true

echo "[reset] baseline restored"
