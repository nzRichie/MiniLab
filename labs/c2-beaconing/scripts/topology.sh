#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs on a machine that has never spawned this lab.
#
# THE OUTSIDE INTERFACES CARRY NO ADDRESSES IN THE FIGURE, and that is the one
# thing about this file that is not mechanical. Which addresses exist out there,
# and which of them is the controller, is what Part 1 has the learner discover
# from a capture. A figure that labelled ext1 and ext2 with their five addresses
# would answer Part 1 before the learner started it, and put the controller in a
# box on page 2. The gateway's own outside address is drawn, because a learner
# needs to know which segment to capture on.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/c2-beaconing
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

# The nodes are pinned so the figure reads inside-to-outside, left to right, the
# direction every flow in this lab travels and the direction the handout
# discusses them in. The automatic layout is free to put the outside segment
# above the inside one, which is not wrong and reads as a hierarchy rather than
# as a boundary; the boundary is the whole subject.
#
# The three workstations are drawn as plain hosts and none of them as a victim,
# because which one is infected is an answer. ext1 and ext2 are drawn the same
# way as each other for the same reason.
add_node_at "$WS1_CTN"    "host"   "workstation"   0    5
add_node_at "$WS2_CTN"    "host"   "workstation"   0    0
add_node_at "$WS3_CTN"    "host"   "workstation"   0   -5
add_node_at "$SW_IN_CTN"  "switch" "switch"        5.5  0
add_node_at "$GW_CTN"     "router" "gateway"       10.5 0
add_node_at "$SW_OUT_CTN" "switch" "switch"        15.5 0
add_node_at "$EXT1_CTN"   "server" "outside host"  21   3
add_node_at "$EXT2_CTN"   "server" "outside host"  21  -3

for w in ws1 ws2 ws3; do
    add_link "$( ctn_of "$w" )" "$WS_IF" "$( ip_of "$w" )/${PREFIXLEN}" \
             "$SW_IN_CTN" "$( sw_port_of "$w" )" ""
done

add_link "$GW_CTN" "$GW_INSIDE_IF" "${GW_INSIDE_IP}/${PREFIXLEN}" \
         "$SW_IN_CTN" "$( sw_port_of gwlan )" ""

add_link "$GW_CTN" "$GW_OUTSIDE_IF" "${GW_OUTSIDE_IP}/${PREFIXLEN}" \
         "$SW_OUT_CTN" "$( sw_port_of gwext )" ""

# Unnumbered on purpose; see the header.
add_link "$EXT1_CTN" "$EXT_IF" "" "$SW_OUT_CTN" "$( sw_port_of ext1 )" ""
add_link "$EXT2_CTN" "$EXT_IF" "" "$SW_OUT_CTN" "$( sw_port_of ext2 )" ""

cat <<JSON
{
  "lab": "c2-beaconing",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
