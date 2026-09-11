#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs in a clean checkout.
#
# The addresses in this figure are the addresses the learner is asked to
# configure, not addresses the lab arrives with. Nothing in the spawned network
# holds any of them until the learner types them in.
#
# Every host is drawn as a plain host, because no device in this lab has a role
# beyond being somewhere a packet has to reach. Both routers are drawn as
# routers, and each subnet's switch as a switch.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/addressing-and-routing
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
add_node() {   # <name> <type> <x> <y>
    nodes+=( "$( printf '    {"name": "%s", "type": "%s", "at": [%s, %s]}' "$1" "$2" "$3" "$4" )" )
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

# Every node is pinned, because the automatic layout has no reason to prefer the
# order the lab is discussed in and stacked this network vertically, with the two
# Middle Net hosts hanging off to one side. The pins put the five devices that
# carry traffic between subnets on one horizontal spine, West on the left and East
# on the right, and hang each subnet's two hosts directly above and below their own
# switch. Coordinates are centimetres, and the spine spacing is set from the node
# box widths topofig.py computes (a router ellipse is 5.42 cm, a rectangle 3.27 cm)
# so that every horizontal link has room for the address at each end.
add_node "$( ctn_of "$SW_WEST" )"       "switch"  0.00   0.00
add_node "$( ctn_of west-router )"      "router"  6.36   0.00
add_node "$( ctn_of "$SW_MID" )"        "switch" 12.72   0.00
add_node "$( ctn_of east-router )"      "router" 19.08   0.00
add_node "$( ctn_of "$SW_EAST" )"       "switch" 25.44   0.00

add_node "$( ctn_of west-1 )" "host"  0.00   3.30
add_node "$( ctn_of west-2 )" "host"  0.00  -3.30
add_node "$( ctn_of mid-1 )"  "host" 12.72   3.30
add_node "$( ctn_of mid-2 )"  "host" 12.72  -3.30
add_node "$( ctn_of east-1 )" "host" 25.44   3.30
add_node "$( ctn_of east-2 )" "host" 25.44  -3.30

# One link per row of lib.sh's wiring table: device to switch, ten of them. The
# switch end of every link carries no address, because a Layer 2 switch forwards
# on MAC addresses and needs none.
for row in "${LINKS[@]}"; do
    set -- $row
    add_link "$( ctn_of "$1" )"  "$2" "$4/${PREFIXLEN}" \
             "$( ctn_of "$3" )"  "$( sw_port_of "$1" )" ""
done

cat <<JSON
{
  "lab": "addressing-and-routing",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
