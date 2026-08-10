#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Every name and address comes from lib.sh, so the handout's figure and the lab
# the learner spawns cannot disagree. Nothing here touches Docker: it reads the
# lab's definitions and prints, so it runs on a machine that has never spawned
# this lab, and in a clean checkout.
#
# Node types (topofig.py fixes the shape and colour of each): router, switch,
# attacker, victim, server, host. The victim is the lab's file server but is drawn
# as `victim`, because whose traffic leaks is what a reader needs to see first.
#
# The layout is pinned because the shape IS the lesson. The two access ports have
# to read as small (one address each) and the uplink as the fat one carrying
# everything beyond S2, and that only lands if the staff and the gateway sit
# together on the far side of a single line. Left to itself the placer has no
# reason to arrange it that way. Everything else stays automatic.
#
# The ten staff machines are drawn as one node on one link. They are ten real
# interfaces on ten real ports of S2 (see spawn.sh), and the handout's addressing
# table lists them; drawing ten parallel lines would bury the one line the figure
# exists to make. The node legend and the link label both give the count and the
# address range so the drawing is a summary and not a contradiction.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/mac-flooding
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
add_link() {   # <a_ctn> <a_if> <a_label> <b_ctn> <b_if> <b_label>   ("" for none)
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips "$3" )" "$4" "$5" "$( json_ips "$6" )" )" )
}
json_ips() {   # quote each label; an empty argument means an unlabelled interface
    local out="" ip
    for ip in "$@"; do [ -n "$ip" ] && out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}

# The two access ports on the left, the uplink across the middle, everything
# beyond S2 on the right. A reader should be able to count addresses per port
# straight off the picture: one, one, and eleven.
# The legend text runs along one row under the figure, and topofig.py checks node
# and label overlaps but not that row's width, so each of these is kept short
# enough that six of them fit the page. The detail they leave out (which port
# carries how many addresses) is in the handout's addressing table.
add_node "$VICTIM_CTN"   "victim"   "the file server"                      -7   3
add_node "$ATTACKER_CTN" "attacker" ""                                     -7  -3
add_node "$SW1_CTN"      "switch"   "access, table of ${MAC_TABLE_SIZE}"    0   0
add_node "$SW2_CTN"      "switch"   "distribution"                          8   0
add_node "$GATEWAY_CTN"  "host"     "the way off site"                     15   3
add_node "$STAFF_CTN"    "host"     "${STAFF_COUNT} machines, ${STAFF_COUNT} ports"  15  -3

# The access ports. Each host-side end carries its address; each switch-side end
# carries the OVS port name the handout tells the learner to type.
add_link "$VICTIM_CTN"   "$VICTIM_IF"   "${VICTIM_IP}/${PREFIXLEN}"   "$SW1_CTN" "$VICTIM_PORT"   ""
add_link "$ATTACKER_CTN" "$ATTACKER_IF" "${ATTACKER_IP}/${PREFIXLEN}" "$SW1_CTN" "$ATTACKER_PORT" ""

# The uplink. Unaddressed on both ends, because it is a switch-to-switch link and
# the whole point of it here is how many OTHER hosts' addresses it carries.
add_link "$SW1_CTN" "$S1_UPLINK_PORT" "" "$SW2_CTN" "$S2_UPLINK_PORT" ""

# Beyond S2. The staff link is labelled with the range rather than one address,
# because it stands for ten of them.
add_link "$GATEWAY_CTN" "$GATEWAY_IF" "${GATEWAY_IP}/${PREFIXLEN}" "$SW2_CTN" "$GATEWAY_PORT" ""
add_link "$STAFF_CTN" "$(staff_if 1)" "$(staff_ip 1)-$(staff_ip "$STAFF_COUNT")" \
         "$SW2_CTN" "$(staff_port 1)" ""

cat <<JSON
{
  "lab": "mac-flooding",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
