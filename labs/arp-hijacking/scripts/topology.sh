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
# The gateway is drawn as a router because that is the role it plays here: it is
# the next hop the victim's traffic is stolen from. The switch ports are Layer 2
# and hold no address, so their a_ip/b_ip list is empty and the figure labels
# that end with the port name.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/arp-hijacking
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

PFX="${SUBNET##*/}"

# The hosts' addresses, keyed by the role name spawn.sh wires.
declare -A HOST_IP=( [attacker]="$ATTACKER_IP" [victim]="$VICTIM_IP" [gateway]="$GW_IP" )

nodes=() links=()
join_lines() {   # the accumulated objects, comma-separated, one per line
    printf '%s' "$1"
    shift
    local x
    for x in "$@"; do printf ',\n%s' "$x"; done
    printf '\n'
}
add_node() {   # <name> <type> [legend]
    local legend=""
    [ -n "${3:-}" ] && legend="$( printf ', "legend": "%s"' "$3" )"
    nodes+=( "$( printf '    {"name": "%s", "type": "%s"%s}' "$1" "$2" "$legend" )" )
}
add_link() {   # <a_ctn> <a_if> <a_ips> <b_ctn> <b_if> <b_ips>   (ips space-separated, "" for none)
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips $3 )" "$4" "$5" "$( json_ips $6 )" )" )
}
json_ips() {   # quote each address; no arguments means an unnumbered interface
    local out="" ip
    for ip in "$@"; do out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}

add_node "$ATTACKER_CTN" "attacker"
add_node "$SW_CTN"       "switch"
add_node "$VICTIM_CTN"   "victim"
add_node "$GATEWAY_CTN"  "router" "gateway"

# One flat broadcast domain: every host hangs off S1 by a veth pair, host side
# named after the switch, switch side named after the host (spawn.sh).
for h in "${HOSTS[@]}"; do
    add_link "$( ctn_of "$h" )" "$HOST_IF" "${HOST_IP[$h]}/${PFX}" \
             "$SW_CTN" "${AS}-${h}" ""
done

cat <<JSON
{
  "lab": "arp-hijacking",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
