#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs on a machine that has never spawned this lab.
#
# The figure is pinned inside on the left and outside on the right, which is the
# direction the callback travels and the direction the handout discusses. The
# appliance is drawn as the victim and the attacker's machine as the attacker;
# ops and mon are plain hosts, because neither has a role in the attack.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/command-injection
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

add_node_at "$WEB_CTN"      "victim"   "appliance"     0    3
add_node_at "$OPS_CTN"      "host"     "operator"      0   -3
add_node_at "$SW_IN_CTN"    "switch"   "switch"        5.5  0
add_node_at "$GW_CTN"       "router"   "gateway"      10.5  0
add_node_at "$SW_OUT_CTN"   "switch"   "switch"       15.5  0
add_node_at "$MON_CTN"      "host"     "monitor"      21    3
add_node_at "$ATTACKER_CTN" "attacker" "listener"     21   -3

for h in "${INSIDE_HOSTS[@]}"; do
    add_link "$( ctn_of "$h" )" "$LAN_IF" "$( ip_of "$h" )/${PREFIXLEN}" \
             "$SW_IN_CTN" "$( sw_port_of "$h" )" ""
done

add_link "$GW_CTN" "$GW_INSIDE_IF" "${GW_INSIDE_IP}/${PREFIXLEN}" \
         "$SW_IN_CTN" "$( sw_port_of gwlan )" ""
add_link "$GW_CTN" "$GW_OUTSIDE_IF" "${GW_OUTSIDE_IP}/${PREFIXLEN}" \
         "$SW_OUT_CTN" "$( sw_port_of gwext )" ""

for h in "${OUTSIDE_HOSTS[@]}"; do
    add_link "$( ctn_of "$h" )" "$EXT_IF" "$( ip_of "$h" )/${PREFIXLEN}" \
             "$SW_OUT_CTN" "$( sw_port_of "$h" )" ""
done

cat <<JSON
{
  "lab": "command-injection",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
