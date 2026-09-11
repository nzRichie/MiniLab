#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs on a machine that has never spawned this lab.
#
# Every address is drawn, including both of the attacker's. Nothing in this lab
# is hidden from the learner: they play the attacker first and the defender
# second on one topology, and the fact that the attacker already holds an
# address on a second outside prefix is something Part 1 tells them outright
# rather than something they are meant to discover.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/intrusion-detection
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

nodes=() links=()
join_lines() {   # the accumulated objects, comma-separated, one per line
    printf '%s' "$1"
    shift
    local x
    for x in "$@"; do printf ',\n%s' "$x"; done
    printf '\n'
}
add_node_at() {   # <name> <type> <legend> <x> <y>
    nodes+=( "$( printf '    {"name": "%s", "type": "%s", "legend": "%s", "at": [%s, %s]}' "$1" "$2" "$3" "$4" "$5" )" )
}
add_link() {   # <a_ctn> <a_if> <a_ips> <b_ctn> <b_if> <b_ips>   ("" for an unnumbered interface)
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips $3 )" "$4" "$5" "$( json_ips $6 )" )" )
}
json_ips() {   # quote each address; no arguments means an unnumbered interface
    local out="" ip
    for ip in "$@"; do out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}

# The nodes are pinned so the figure reads inside on the left and outside on the
# right, which is the direction every packet the lab discusses travels and the
# direction the handout discusses them in. The automatic layout is free to stack
# the two segments, which reads as a hierarchy rather than as a boundary, and
# the boundary is what every rule in the lab is written about.
add_node_at "$SERVER_CTN"   "victim"   "the server under attack"     0    3
add_node_at "$CLIENT_CTN"   "host"     "internal workstation"        0   -3
add_node_at "$SW_IN_CTN"    "switch"   "switch"                      5.5  0
add_node_at "$RTR_CTN"      "router"   "router"                     10.5  0
add_node_at "$SW_OUT_CTN"   "switch"   "switch"                     15.5  0
add_node_at "$ATTACKER_CTN" "attacker" "the outside machine"        21    3
add_node_at "$CUSTOMER_CTN" "host"     "outside reader of the site" 21   -3

add_link "$SERVER_CTN" "$LAN_IF" "${SERVER_IP}/${PREFIXLEN}" \
         "$SW_IN_CTN" "$( sw_port_of server )" ""
add_link "$CLIENT_CTN" "$LAN_IF" "${CLIENT_IP}/${PREFIXLEN}" \
         "$SW_IN_CTN" "$( sw_port_of client )" ""
add_link "$RTR_CTN" "$RTR_INSIDE_IF" "${RTR_INSIDE_IP}/${PREFIXLEN}" \
         "$SW_IN_CTN" "$( sw_port_of rtrlan )" ""

add_link "$RTR_CTN" "$RTR_OUTSIDE_IF" "${RTR_OUTSIDE_IP}/${PREFIXLEN} ${RTR_OUTSIDE_ALT_IP}/${PREFIXLEN}" \
         "$SW_OUT_CTN" "$( sw_port_of rtrext )" ""
add_link "$ATTACKER_CTN" "$EXT_IF" "${ATTACKER_IP}/${PREFIXLEN} ${ATTACKER_ALT_IP}/${PREFIXLEN}" \
         "$SW_OUT_CTN" "$( sw_port_of attacker )" ""
add_link "$CUSTOMER_CTN" "$EXT_IF" "${CUSTOMER_IP}/${PREFIXLEN}" \
         "$SW_OUT_CTN" "$( sw_port_of customer )" ""

cat <<JSON
{
  "lab": "intrusion-detection",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
