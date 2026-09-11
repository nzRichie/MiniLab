#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs on a machine that has never spawned this lab.
#
# The appliance is drawn as the victim and the attacker's machine as the
# attacker. The operator's workstation is a plain host: it sends the one
# legitimate request the lab measures against and has no part in the attack.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/stack-overflow
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

nodes=() links=()
join_lines() {
    printf '%s' "$1"; shift
    local x
    for x in "$@"; do printf ',\n%s' "$x"; done
    printf '\n'
}
add_node_at() {   # <name> <type> <legend> <x> <y>
    nodes+=( "$( printf '    {"name": "%s", "type": "%s", "legend": "%s", "at": [%s, %s]}' "$1" "$2" "$3" "$4" "$5" )" )
}
add_link() {   # <a_ctn> <a_if> <a_ips> <b_ctn> <b_if> <b_ips>
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips $3 )" "$4" "$5" "$( json_ips $6 )" )" )
}
json_ips() {
    local out="" ip
    for ip in "$@"; do out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}

add_node() {   # <name> <type> <legend>   -- placement left to the generator
    nodes+=( "$( printf '    {"name": "%s", "type": "%s", "legend": "%s"}' "$1" "$2" "$3" )" )
}

# The three hosts sit in a row above the switch, in the order the handout talks
# about them: the appliance under attack, the operator who sends the one
# legitimate request, and the machine the overflow comes from. Left to itself
# the generator produces the same shape with the row in the opposite order.
add_node_at "$SVC_CTN"      "victim"   "appliance"    0    4
add_node_at "$OPS_CTN"      "host"     "operator"     6.5  4
add_node_at "$ATTACKER_CTN" "attacker" "attacker"    13    4
add_node_at "$SW_CTN"       "switch"   "switch"       6.5  0

for h in "${HOSTS[@]}"; do
    add_link "$( ctn_of "$h" )" "$LAN_IF" "$( ip_of "$h" )/${PREFIXLEN}" \
             "$SW_CTN" "$( sw_port_of "$h" )" ""
done

cat <<JSON
{
  "lab": "stack-overflow",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
