#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs on a machine that has never spawned this lab.
#
# Every address is drawn, the collector's included: unlike the c2 lab, the
# destination is not a thing the learner discovers -- the handout names the zone
# and the operator's server, because Part 1 has the learner drive the channel by
# hand. What the figure shows is the boundary the gateway sits on, inside on the
# left and outside on the right, the direction the file travels.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/dns-tunnelling
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

# Pinned inside-to-outside, left to right, the direction the file travels and the
# direction the handout discusses. ws1 is the compromised workstation the file
# leaves from and collector is where it ends up, so both are drawn as the
# operator's own machines; the resolver and pub serve DNS; ws2 has no role.
add_node_at "$WS1_CTN"       "attacker" "compromised host" 0    5
add_node_at "$WS2_CTN"       "host"     "workstation"      0    0
add_node_at "$RESOLVER_CTN"  "server"   "resolver"         0   -5
add_node_at "$SW_IN_CTN"     "switch"   "switch"           5.5  0
add_node_at "$GW_CTN"        "router"   "gateway"          10.5 0
add_node_at "$SW_OUT_CTN"    "switch"   "switch"           15.5 0
add_node_at "$PUB_CTN"       "server"   "example.lab"      21   3
add_node_at "$COLLECTOR_CTN" "attacker" "collector"        21  -3

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
  "lab": "dns-tunnelling",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
