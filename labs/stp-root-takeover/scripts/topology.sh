#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Every name and address comes from lib.sh, so the handout's figure and the lab
# the learner spawns cannot disagree. Nothing here touches Docker: it reads the
# lab's definitions and prints, so it runs on a machine that has never spawned
# this lab, and in a clean checkout.
#
# Node types (topofig.py fixes the shape and colour of each): router, switch,
# attacker, victim, server, host. The gateway is a plain `host`: the lab is about
# the path to it, not about anything it serves.
#
# The layout is pinned because the shape IS the lesson. Three switches in a ring
# with the attacker slung underneath both lower switches is what makes the
# redundant path, the blocked port and the attacker's two links legible at a
# glance; left to itself the placer has no reason to prefer a ring that reads as
# a ring. Everything else stays automatic.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/stp-root-takeover
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

# S1 on top with the other two below it, so the ring reads as a ring and the
# intended root sits where a reader looks first. The attacker hangs below the two
# lower switches, straddling them, which is the position Part 2 is about.
add_node "$SW1_CTN"      "switch"   "intended root, priority ${PRIO_SW1}"   6   7
add_node "$SW2_CTN"      "switch"   "priority ${PRIO_SW2}"                  0   0
add_node "$SW3_CTN"      "switch"   "priority ${PRIO_SW3}"                 12   0
add_node "$VICTIM_CTN"   "victim"   ""                                     -6   0
add_node "$GATEWAY_CTN"  "host"     "the far end of the victim's path"     18   0
add_node "$ATTACKER_CTN" "attacker" ""                                      6  -7

# The ring. Unlabelled ports on both ends: which of the three links STP blocks is
# what the learner works out from `ovs-appctl stp/show`, so the figure showing a
# blocked link would give away the first thing the lab asks.
add_link "$SW1_CTN" "$(sw_port_of "$SW2")" "" "$SW2_CTN" "$(sw_port_of "$SW1")" ""
add_link "$SW1_CTN" "$(sw_port_of "$SW3")" "" "$SW3_CTN" "$(sw_port_of "$SW1")" ""
add_link "$SW2_CTN" "$(sw_port_of "$SW3")" "" "$SW3_CTN" "$(sw_port_of "$SW2")" ""

# The hosts. The host-side end carries the address; the switch-side end carries
# the OVS port name the handout tells the learner to type.
add_link "$VICTIM_CTN"  "$VICTIM_IF"  "${VICTIM_IP}/${PREFIXLEN}"  "$SW2_CTN" "$VICTIM_PORT"  ""
add_link "$GATEWAY_CTN" "$GATEWAY_IF" "${GATEWAY_IP}/${PREFIXLEN}" "$SW3_CTN" "$GATEWAY_PORT" ""

# The attacker's two links. Link A carries its address; link B is labelled with
# the state it starts in, because "this link is down until you raise it" is the
# single most important thing the figure can tell a reader about Part 2.
add_link "$ATTACKER_CTN" "$ATTACKER_IF_A" "${ATTACKER_IP}/${PREFIXLEN}" "$SW2_CTN" "$ATT_PORT_S2" ""
add_link "$ATTACKER_CTN" "$ATTACKER_IF_B" "down until Part 2"           "$SW3_CTN" "$ATT_PORT_S3" ""

cat <<JSON
{
  "lab": "stp-root-takeover",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
