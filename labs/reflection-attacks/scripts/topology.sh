#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Every name and address comes from lib.sh, so the handout's figure and the lab
# the learner spawns cannot disagree. Nothing here touches Docker: it reads the
# lab's definitions and prints, so it runs on a machine that has never spawned
# this lab, and in a clean checkout.
#
# Node types (topofig.py fixes the shape and colour of each): router, switch,
# attacker, victim, server, host. "legend" overrides the key text for a node.
# An interface with no address (the OVS ports on S1) is drawn from its interface
# name instead, which is why a_ip/b_ip is allowed to be null.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/reflection-attacks
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

# The core hosts' addresses, keyed by the role name spawn.sh wires.
declare -A CORE_IP=( [victim]="$VICTIM_IP" [dns]="$DNS_IP" [ntp]="$NTP_IP" )

links=()
emit_links() {   # the accumulated link objects, comma-separated, one per line
    printf '%s' "${links[0]}"
    local l
    for l in "${links[@]:1}"; do printf ',\n%s' "$l"; done
    printf '\n'
}
add_link() {   # <a_ctn> <a_if> <a_ip|-> <b_ctn> <b_if> <b_ip|->
    local aip="null" bip="null"
    [ "$3" != "-" ] && aip="\"$3\""
    [ "$6" != "-" ] && bip="\"$6\""
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": %s, "b": "%s", "b_if": "%s", "b_ip": %s}' \
        "$1" "$2" "$aip" "$4" "$5" "$bip" )" )
}

# Customer edge: point-to-point, no switch. This is the link the defence guards.
add_link "$ATTACKER_CTN" "$ATT_IF" "${ATTACKER_IP}/${PREFIXLEN}" \
         "$ROUTER_CTN"   "$R_CUST_IF" "${ROUTER_CUST_IP}/${PREFIXLEN}"

# Core segment: the router and every core host attach to S1. The switch ports are
# Layer 2 and hold no address.
add_link "$ROUTER_CTN" "$R_CORE_IF" "${ROUTER_CORE_IP}/${PREFIXLEN}" \
         "$SW_CTN" "$( sw_port_of router )" "-"
for h in "${CORE_HOSTS[@]}"; do
    add_link "$( ctn_of "$h" )" "$HOST_IF" "${CORE_IP[$h]}/${PREFIXLEN}" \
             "$SW_CTN" "$( sw_port_of "$h" )" "-"
done

cat <<JSON
{
  "lab": "reflection-attacks",
  "nodes": [
    {"name": "$ATTACKER_CTN", "type": "attacker"},
    {"name": "$ROUTER_CTN",   "type": "router"},
    {"name": "$SW_CTN",       "type": "switch"},
    {"name": "$DNS_CTN",      "type": "server", "legend": "reflector"},
    {"name": "$NTP_CTN",      "type": "server", "legend": "reflector"},
    {"name": "$VICTIM_CTN",   "type": "victim"}
  ],
  "links": [
$( emit_links )
  ]
}
JSON
