#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs in a clean checkout.
#
# The server is drawn as a `server` because it is the one node running this
# lab's services and the one node the learner configures. The admin station and
# the outside host are plain hosts: neither has a role beyond being a place a
# probe is sent from, and neither attacks anything.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/vps-hardening
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

nodes=() links=()
join_lines() {
    printf '%s' "$1"
    shift
    local x
    for x in "$@"; do printf ',\n%s' "$x"; done
    printf '\n'
}
add_node() {   # <name> <type> <legend> <x> <y>
    nodes+=( "$( printf '    {"name": "%s", "type": "%s", "legend": "%s", "at": [%s, %s]}' \
        "$1" "$2" "$3" "$4" "$5" )" )
}
add_link() {   # <a_ctn> <a_if> <a_ip> <b_ctn> <b_if> <b_ip>
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": ["%s"], "b": "%s", "b_if": "%s", "b_ip": ["%s"]}' \
        "$1" "$2" "$3" "$4" "$5" "$6" )" )
}

# Every node is pinned. The automatic layout put the router at the top with all
# three links fanning downward, which reads as a hierarchy the lab does not have.
# The pins put the two vantages every sweep is run from at the two ends of one
# horizontal line with the router between them, matching the order the handout
# discusses them in, and hang the management client below the router because its
# segment is the one the SSH rule names rather than a third point on that line.
# Coordinates are centimetres; the spacing is set from the node box widths
# topofig.py computes, so each horizontal link has room for the address at each
# end.
add_node "$OUTSIDE_CTN" "host"   "outside the site"       0.00   0.00
add_node "$ROUTER_CTN"  "router" "forwards, filters nothing"  7.20   0.00
add_node "$SERVER_CTN"  "server" "the machine you harden" 14.40   0.00
add_node "$ADMIN_CTN"   "host"   "management client"       7.20  -3.40

add_link "$OUTSIDE_CTN" "$OUT_IF"   "${OUTSIDE_IP}/${PREFIXLEN}" \
         "$ROUTER_CTN"  "$R_EXT_IF" "${ROUTER_EXT_IP}/${PREFIXLEN}"
add_link "$SERVER_CTN"  "$SRV_IF"   "${SERVER_IP}/${PREFIXLEN}" \
         "$ROUTER_CTN"  "$R_SRV_IF" "${ROUTER_SRV_IP}/${PREFIXLEN}"
add_link "$ADMIN_CTN"   "$ADMIN_IF"  "${ADMIN_IP}/${PREFIXLEN}" \
         "$ROUTER_CTN"  "$R_MGMT_IF" "${ROUTER_MGMT_IP}/${PREFIXLEN}"

cat <<JSON
{
  "lab": "vps-hardening",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
