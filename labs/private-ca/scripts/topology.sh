#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs in a clean checkout.
#
# The CA and the web server are both drawn as `server`, and they therefore share
# one legend entry rather than carrying one each. A per-node legend overrides the
# key text for that node's TYPE, so two `server` nodes with different legends
# emit two entries for one colour and the second overprints the first. What the
# two machines each run is in the handout's addressing table, which is where a
# reader looks for it anyway. The client is a plain host: it runs no service, and
# its only job is deciding whether to believe what the web server presents.
# Nothing here is an attacker or a victim; this lab has neither.
#
# The three switch ports carry no address, which is what the empty address list
# says; topofig.py labels those ends with the port name in italics.
#
# All four nodes are pinned. The automatic layout put the client on the left and
# the CA on the right, which is the reverse of both the addressing table and the
# order the lab works in: the authority issues, the server presents, the client
# checks. Coordinates are centimetres.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/private-ca
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

add_node "$CA_CTN"      "server"  0.00   0.00  "runs a service"
add_node "$SERVER_CTN"  "server"  7.20   0.00  "runs a service"
add_node "$CLIENT_CTN"  "host"   14.40   0.00  "runs no service"
add_node "$SW_CTN"      "switch"  7.20  -3.60

add_link "$CA_CTN"     "$HOST_IF" "${CA_IP}/${PREFIXLEN}"     "$SW_CTN" "${AS}-ca"     ""
add_link "$SERVER_CTN" "$HOST_IF" "${SERVER_IP}/${PREFIXLEN}" "$SW_CTN" "${AS}-server" ""
add_link "$CLIENT_CTN" "$HOST_IF" "${CLIENT_IP}/${PREFIXLEN}" "$SW_CTN" "${AS}-client" ""

cat <<JSON
{
  "lab": "private-ca",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
