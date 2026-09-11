#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Every name and address comes from lib.sh, so the handout's figure and the lab
# the learner spawns cannot disagree. Nothing here touches Docker: it reads the
# lab's definitions and prints, so it runs on a machine that has never spawned
# this lab, and in a clean checkout.
#
# The addresses in this figure are the addresses the learner is asked to
# configure, not addresses the lab arrives with. Nothing in the spawned network
# holds any of them until the learner types them in; that is the whole exercise.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/ospf-routing
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
add_node() {   # <name> <type> [legend] [x y]
    local legend="" at=""
    [ -n "${3:-}" ] && legend="$( printf ', "legend": "%s"' "$3" )"
    [ -n "${4:-}" ] && at="$( printf ', "at": [%s, %s]' "$4" "$5" )"
    nodes+=( "$( printf '    {"name": "%s", "type": "%s"%s%s}' "$1" "$2" "$legend" "$at" )" )
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

# Every node is pinned, because this network is a ring and the automatic layout
# has no reason to draw it as one. The five routers sit on a pentagon in the order
# the ring runs (LOND at the top, then clockwise NEWY, ZURI, TRGA, PARI), so the
# two ways round from LOND to ZURI -- which is the whole of Part 3 -- are the two
# ways round the figure. The chord PARI-NEWY closes the four-node cycle across the
# top, which is where the equal-cost pairs come from.
#
# Each host is pinned on the same radius as its router, further out, so a host
# hangs off its own router and no host lands inside the ring where it would be
# read as part of the routing topology.
#
# Coordinates are centimetres on a pentagon of radius 7.5, hosts on the same
# bearing at radius 12.5. The radii are as small as the generator will accept
# without a label collision (radius 7 with hosts at 11.5 fails, on the host-link
# addresses at NEWY and ZURI): the figure is scaled to the text width when it is placed, so
# every centimetre of bounding box costs font size in the rendered handout, and at
# radius 9 with hosts at 16 the container names came out too small to read.
declare -A RX RY HX HY
RX[lond]=0.00;   RY[lond]=7.50;    HX[lond]=0.00;    HY[lond]=12.50
RX[newy]=7.13;   RY[newy]=2.32;    HX[newy]=11.89;    HY[newy]=3.86
RX[zuri]=4.41;   RY[zuri]=-6.07;    HX[zuri]=7.35;    HY[zuri]=-10.11
RX[trga]=-4.41;   RY[trga]=-6.07;    HX[trga]=-7.35;    HY[trga]=-10.11
RX[pari]=-7.13;   RY[pari]=2.32;    HX[pari]=-11.89;    HY[pari]=3.86

# Every node carries a plain type. No host in this lab has a role beyond being
# somewhere a packet has to reach, and no router has one beyond forwarding, so
# nothing here should be coloured as though it did.
for r in "${ROUTERS[@]}"; do
    add_node "$( router_ctn "$r" )" "router" "" "${RX[$r]}" "${RY[$r]}"
    add_node "$( host_ctn "$r" )"   "host"   "" "${HX[$r]}" "${HY[$r]}"
done

# Router-to-router links: a /30 each, router a's interface toward b named port_<B>.
while read -r a b a_ip b_ip subnet delay; do
    [ -z "$a" ] && continue
    add_link "$( router_ctn "$a" )" "$( peer_if "$b" )" "${a_ip}/${LINK_PREFIXLEN}" \
             "$( router_ctn "$b" )" "$( peer_if "$a" )" "${b_ip}/${LINK_PREFIXLEN}"
done < <( each_link )

# Host links: each router to its own host, on that router's own /24.
for r in "${ROUTERS[@]}"; do
    add_link "$( router_ctn "$r" )" "$HOST_IF_ROUTER" "$( host_gw "$r" )/${HOST_PREFIXLEN}" \
             "$( host_ctn "$r" )"   "$HOST_IF_HOST"   "$( host_ip "$r" )/${HOST_PREFIXLEN}"
done

cat <<JSON
{
  "lab": "ospf-routing",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
