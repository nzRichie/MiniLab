#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Copy this into the new lab's scripts/, then replace the node and link blocks
# with the lab's own. Everything must come from lib.sh, so the figure and the lab
# the learner spawns cannot disagree. Nothing here touches Docker: it reads the
# lab's definitions and prints, so it runs on a machine that has never spawned
# this lab, and in a clean checkout.
#
# Node "type" fixes both the shape and the colour topofig.py draws, and the key
# it prints at the foot of the figure:
#
#   router    ellipse, blue      switch    rounded rectangle, green
#   attacker  rectangle, red     victim    rectangle, amber
#   server    rectangle, violet  host      rectangle, grey (a host with no role)
#
# Optional per node:
#   "legend": "reflector"   overrides the key text for that node's type
#   "at": [x, y]            pins the node, in cm, when the automatic layout reads
#                           badly. Try without it first; most labs never need it.
#
# a_ip / b_ip is a LIST, because one interface can carry more than one address.
# Leave it empty for an interface with no address (a switch port, or a defender
# interface the learner configures later); the figure then labels that end with
# the interface name in italics and says so in the key.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/<lab>
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
add_node() {   # <name> <type> [legend]
    local legend=""
    [ -n "${3:-}" ] && legend="$( printf ', "legend": "%s"' "$3" )"
    nodes+=( "$( printf '    {"name": "%s", "type": "%s"%s}' "$1" "$2" "$legend" )" )
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

# --- replace from here -----------------------------------------------------
# There is no attacker and no victim in this lab, so no node is coloured as
# either: it is a configuration exercise, and every machine here belongs to the
# site's operators. The workstation and the bastion are drawn as plain hosts for
# the same reason, and app is a `server` because it is the one machine running a
# service the lab sweeps for beyond sshd.
# The legend carries one entry per TYPE, not per node, and the entries share a
# single row under the figure. Two nodes of the same type given different legend
# text overprint each other there, and a long entry overprints its neighbour, so
# the only override here is on `server`, whose default word does not say what
# distinguishes app from the other machines.
add_node "$WS_CTN"      "host"
add_node "$EDGE_CTN"    "router"
add_node "$BASTION_CTN" "host"
add_node "$SW_CTN"      "switch"
add_node "$APP_CTN"     "server" "runs a service"
add_node "$DB_CTN"      "host"

add_link "$WS_CTN"   "$WS_IF"     "${WS_IP}/${PREFIXLEN}" \
         "$EDGE_CTN" "$E_EXT_IF"  "${EDGE_EXT_IP}/${PREFIXLEN}"
add_link "$BASTION_CTN" "$BASTION_IF" "${BASTION_IP}/${PREFIXLEN}" \
         "$EDGE_CTN"    "$E_DMZ_IF"   "${EDGE_DMZ_IP}/${PREFIXLEN}"
add_link "$EDGE_CTN" "$E_INNER_IF" "${EDGE_INNER_IP}/${PREFIXLEN}" \
         "$SW_CTN"   "$( sw_port_of edge )" ""
add_link "$APP_CTN" "$APP_IF" "${APP_IP}/${PREFIXLEN}" \
         "$SW_CTN"  "$( sw_port_of app )" ""
add_link "$DB_CTN" "$DB_IF" "${DB_IP}/${PREFIXLEN}" \
         "$SW_CTN" "$( sw_port_of db )" ""
# --- to here ---------------------------------------------------------------

cat <<JSON
{
  "lab": "bastion-access",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
