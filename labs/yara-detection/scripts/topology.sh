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
# No node in this lab is an attacker or a victim: the corpus is a set of files
# and the only traffic on the wire is Part 4's two uploads. The scanner is the
# one machine that serves anything, so it is the only "server"; the other three
# are plain hosts, which is what the grey is for.
add_node "$SCANNER_CTN"     "server" "upload scanner"
add_node "$WORKSTATION_CTN" "host"
add_node "$CLIENT_CTN"      "host"
add_node "$HOLDOUT_CTN"     "host"
add_node "$SW_CTN"          "switch"

for role in workstation scanner client holdout; do
    add_link "$( ctn_of "$role" )" "$LAN_IF" "$( ip_of "$role" )/${PREFIXLEN}" \
             "$SW_CTN" "$( sw_port_of "$role" )" ""
done
# --- to here ---------------------------------------------------------------

cat <<JSON
{
  "lab": "yara-detection",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
