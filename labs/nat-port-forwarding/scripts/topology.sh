#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs in a clean checkout.
#
# Both machines that run a web service are drawn as `server` and therefore share
# one legend entry rather than carrying one each. A per-node legend overrides the
# key text for that node's TYPE, so two `server` nodes with different legends
# emit two entries for one colour and the second overprints the first. Which one
# is inside the site and which is beyond it is what the figure's left-to-right
# arrangement says, and the addressing table says the rest.
#
# The two clients are plain hosts: they run no service, and nothing in this lab
# is an attacker or a victim.
#
# Every node is pinned, left to right in the order the lab reads: the private
# machines, the switch they share, the router, and the one machine beyond it. The
# automatic layout stacked the private segment above the router and put the
# outside host in the bottom corner beside it, which draws the two segments as
# one shape and hides the only boundary the lab is about. Coordinates are
# centimetres.
#
# The switch's four ports carry no address, which is what the empty address list
# says; topofig.py labels those ends with the port name in italics.
#
# Re-run after any topology change:
#   labs/tools/topofig.py labs/catalogue/nat-port-forwarding
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
add_node() {   # <name> <type> <x> <y> [legend]
    local legend=""
    [ -n "${5:-}" ] && legend="$( printf ', "legend": "%s"' "$5" )"
    nodes+=( "$( printf '    {"name": "%s", "type": "%s", "at": [%s, %s]%s}' \
        "$1" "$2" "$3" "$4" "$legend" )" )
}
json_ips() {   # quote each address; no arguments means an unnumbered interface
    local out="" ip
    for ip in "$@"; do out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}
add_link() {   # <a_ctn> <a_if> <a_ips> <b_ctn> <b_if> <b_ips>
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips $3 )" "$4" "$5" "$( json_ips $6 )" )" )
}

add_node "$WEB_CTN"     "server"  0.00   3.60  "runs a web service"
add_node "$INSIDE1_CTN" "host"    0.00   0.00
add_node "$INSIDE2_CTN" "host"    0.00  -3.60
add_node "$SW_CTN"      "switch"  5.60   0.00
add_node "$ROUTER_CTN"  "router" 11.20   0.00
add_node "$OUTSIDE_CTN" "server" 16.80   0.00  "runs a web service"

add_link "$INSIDE1_CTN" "$HOST_IF" "${INSIDE1_IP}/${PREFIXLEN}" \
         "$SW_CTN"      "$( sw_port_of inside-1 )"  ""
add_link "$INSIDE2_CTN" "$HOST_IF" "${INSIDE2_IP}/${PREFIXLEN}" \
         "$SW_CTN"      "$( sw_port_of inside-2 )"  ""
add_link "$WEB_CTN"     "$HOST_IF" "${WEB_IP}/${PREFIXLEN}" \
         "$SW_CTN"      "$( sw_port_of webserver )" ""
add_link "$ROUTER_CTN"  "$R_IN_IF" "${ROUTER_IN_IP}/${PREFIXLEN}" \
         "$SW_CTN"      "$( sw_port_of router )"    ""
add_link "$ROUTER_CTN"  "$R_OUT_IF" "${ROUTER_OUT_IP}/${PREFIXLEN}" \
         "$OUTSIDE_CTN" "$OUT_IF"   "${OUTSIDE_IP}/${PREFIXLEN}"

cat <<JSON
{
  "lab": "nat-port-forwarding",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
