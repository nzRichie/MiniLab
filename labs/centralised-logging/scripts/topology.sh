#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs in a clean checkout.
#
# The collector is drawn as `server`, because it is the machine the lab's
# protocol is served by, and it is the one node whose role a reader should pick
# out before reading a container name. `web` is a `server` too and neither
# carries a per-node legend: a legend on one node overrides the key text for the
# whole TYPE, so giving only the collector one produced two legend swatches in
# the same colour, "runs a service" beside "server", for one node type.
#
# `db` is drawn as `victim`, because it is the machine the incident happens to
# and the one whose local record is destroyed. Nothing here is an `attacker`:
# this lab spawns no attacker container, and the login attempts come from `web`,
# a machine whose own role in the lab is to be an ordinary web service.
#
# Every node is pinned. The automatic layout puts four leaves around one switch
# in a cross, which reads as four equivalent machines; the lab's shape is one
# collector on one side and three machines that report to it on the other, and
# the figure says that only if the collector is placed alone. Coordinates are
# centimetres.
#
# The switch's four ports carry no address, which is what the empty address list
# says; topofig.py labels those ends with the port name in italics.
#
# Re-run after any topology change:
#   labs/tools/topofig.py labs/catalogue/centralised-logging
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

add_node "$COLLECTOR_CTN" "server"  0.00   0.00
add_node "$SW_CTN"        "switch"  6.20   0.00
add_node "$ADMIN_CTN"     "host"   12.40   4.20
add_node "$WEB_CTN"       "server" 12.40   0.00
add_node "$DB_CTN"        "victim" 12.40  -4.20

add_link "$COLLECTOR_CTN" "$HOST_IF" "${COLLECTOR_IP}/${PREFIXLEN}" \
         "$SW_CTN"        "$( sw_port_of collector )" ""
add_link "$ADMIN_CTN"     "$HOST_IF" "${ADMIN_IP}/${PREFIXLEN}" \
         "$SW_CTN"        "$( sw_port_of admin )"     ""
add_link "$WEB_CTN"       "$HOST_IF" "${WEB_IP}/${PREFIXLEN}" \
         "$SW_CTN"        "$( sw_port_of web )"       ""
add_link "$DB_CTN"        "$HOST_IF" "${DB_IP}/${PREFIXLEN}" \
         "$SW_CTN"        "$( sw_port_of db )"        ""

cat <<JSON
{
  "lab": "centralised-logging",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
