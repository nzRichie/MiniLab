#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab a learner spawns
# cannot disagree. Nothing here touches Docker: it runs on a machine that has
# never spawned this lab.
#
# The figure draws all three legs and their addresses. Unlike c2-beaconing, this
# lab hides no address in the topology: the learner is running the botnet, not
# hunting it, so which host is which is not an answer. What is an answer -- the
# password layout, and which host holds the loot -- is nowhere in the figure
# because it is nowhere in any address.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/botnet
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
add_link() {      # <a_ctn> <a_if> <a_ips> <b_ctn> <b_if> <b_ips>
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips $3 )" "$4" "$5" "$( json_ips $6 )" )" )
}
json_ips() {
    local out="" ip
    for ip in "$@"; do out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}

# The router sits at the centre. The inside leg goes left, the operator leg
# right, and the field leg down, so the figure reads as three segments meeting
# at the one machine that sees between them, which is the lab's whole subject.
add_node_at "$SERVER_CTN"    "server" "inside server"      0    3
add_node_at "$SW_INSIDE_CTN" "switch" "inside switch"      6    3
add_node_at "$ROUTER_CTN"    "router" "router"            13    3

add_node_at "$SW_OP_CTN"     "switch" "operator switch"   20    3
add_node_at "$C2_CTN"        "host"   "controller"        26    5.5
add_node_at "$LOADER_CTN"    "host"   "payload host"      26    0.5

add_node_at "$SW_FIELD_CTN"  "switch" "field switch"      13   -5
add_node_at "$( ctn_of host1 )" "host" "field host"       -4  -13
add_node_at "$( ctn_of host2 )" "host" "field host"        1  -14
add_node_at "$( ctn_of host3 )" "host" "field host"        7  -14.5
add_node_at "$( ctn_of host4 )" "host" "field host"       13  -14.5
add_node_at "$( ctn_of host5 )" "host" "field host"       19  -14.5
add_node_at "$( ctn_of host6 )" "host" "field host"       25  -14
add_node_at "$ADMIN_CTN"     "host"   "admin workstation" 31  -12

# --- inside leg -----------------------------------------------------------
add_link "$SERVER_CTN" "$IF_INSIDE" "${SERVER_IP}/${PREFIXLEN}" \
         "$SW_INSIDE_CTN" "$( sw_port_of server )" ""
add_link "$ROUTER_CTN" "$IF_INSIDE" "${R_INSIDE_IP}/${PREFIXLEN}" \
         "$SW_INSIDE_CTN" "$( sw_port_of router-in )" ""

# --- operator leg ---------------------------------------------------------
add_link "$ROUTER_CTN" "$IF_OP" "${R_OP_IP}/${PREFIXLEN}" \
         "$SW_OP_CTN" "$( sw_port_of router-op )" ""
add_link "$C2_CTN" "$IF_OP" "${C2_IP}/${PREFIXLEN}" \
         "$SW_OP_CTN" "$( sw_port_of c2 )" ""
add_link "$LOADER_CTN" "$IF_OP" "${LOADER_IP}/${PREFIXLEN}" \
         "$SW_OP_CTN" "$( sw_port_of loader )" ""

# --- field leg ------------------------------------------------------------
add_link "$ROUTER_CTN" "$IF_FIELD" "${R_FIELD_IP}/${PREFIXLEN}" \
         "$SW_FIELD_CTN" "$( sw_port_of router-fld )" ""
for h in host1 host2 host3 host4 host5 host6; do
    add_link "$( ctn_of "$h" )" "$IF_FIELD" "$( ip_of "$h" )/${PREFIXLEN}" \
             "$SW_FIELD_CTN" "$( sw_port_of "$h" )" ""
done
add_link "$ADMIN_CTN" "$IF_FIELD" "${ADMIN_IP}/${PREFIXLEN}" \
         "$SW_FIELD_CTN" "$( sw_port_of admin )" ""

cat <<JSON
{
  "lab": "botnet",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
