#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs on a machine that has never spawned this lab, and in a
# clean checkout.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/authoritative-dns
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
# either: it is a configuration exercise, and every machine belongs to the same
# operators. Four machines run named and are drawn as servers; the client is a
# plain host, because what it runs is the measuring instrument rather than one of
# the lab's subjects.
#
# The legend carries one entry per TYPE, not per node. All four `server` nodes
# therefore carry the SAME override text: giving it to one of them and leaving
# the others on the default put two entries on one swatch, "runs named" beside
# "server", which reads as two kinds of node when there is one.
add_node "$ROOT_CTN"      "server" "runs named"
add_node "$PRIMARY_CTN"   "server" "runs named"
add_node "$SECONDARY_CTN" "server" "runs named"
add_node "$SUB_CTN"       "server" "runs named"
add_node "$CLIENT_CTN"    "host"
add_node "$SW_CTN"        "switch"

# Only the IPv4 address is drawn. Every machine also holds the matching
# fd00:115::<last octet> address, which the addressing table beside the figure
# gives in full; putting both on the figure doubles every label for one record
# type's worth of information.
add_link "$ROOT_CTN"      "$HOST_IF" "${ROOT_IP}/${PREFIXLEN}" \
         "$SW_CTN"        "$( sw_port_of root )" ""
add_link "$PRIMARY_CTN"   "$HOST_IF" "${PRIMARY_IP}/${PREFIXLEN}" \
         "$SW_CTN"        "$( sw_port_of primary )" ""
add_link "$SECONDARY_CTN" "$HOST_IF" "${SECONDARY_IP}/${PREFIXLEN}" \
         "$SW_CTN"        "$( sw_port_of secondary )" ""
add_link "$SUB_CTN"       "$HOST_IF" "${SUB_IP}/${PREFIXLEN}" \
         "$SW_CTN"        "$( sw_port_of sub )" ""
add_link "$CLIENT_CTN"    "$HOST_IF" "${CLIENT_IP}/${PREFIXLEN}" \
         "$SW_CTN"        "$( sw_port_of client )" ""
# --- to here ---------------------------------------------------------------

cat <<JSON
{
  "lab": "authoritative-dns",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
