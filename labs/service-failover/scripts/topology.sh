#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs on a machine that has never spawned this lab.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/service-failover
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

# The proxy is drawn as the router type because that is the shape its position
# earns: it is the only machine with a foot in both segments and the only path
# between them. The legend says what it actually is, because it forwards nothing
# and every packet that crosses it crosses as the payload of a connection it
# opened itself.
# The key prints one entry per legend string, side by side under the figure, so
# each one has to be a label rather than a sentence.
#
# The nodes are pinned left to right in the order a request travels: the client
# asks the proxy, the proxy opens its own connection to a backend over the
# switch. The automatic layout put the client to the right of the proxy and the
# backends below it, which is not wrong but reads as a tree rather than as a path,
# and the path is what the whole lab is about.
add_node_at() {   # <name> <type> <legend> <x> <y>
    nodes+=( "$( printf '    {"name": "%s", "type": "%s", "legend": "%s", "at": [%s, %s]}' "$1" "$2" "$3" "$4" "$5" )" )
}

add_node_at "$CLIENT_CTN" "host"   "client"        0   0
add_node_at "$PROXY_CTN"  "router" "reverse proxy" 5.5 0
add_node_at "$SW_CTN"     "switch" "switch"        9.5 0
add_node_at "$WEB1_CTN"   "server" "backend"       13 4.2
add_node_at "$WEB2_CTN"   "server" "backend"       13 -4.2

add_link "$CLIENT_CTN" "$CLIENT_IF" "${CLIENT_IP}/${PREFIXLEN}" \
         "$PROXY_CTN"  "$P_FRONT_IF" "${PROXY_FRONT_IP}/${PREFIXLEN}"

add_link "$PROXY_CTN" "$P_BACK_IF" "${PROXY_BACK_IP}/${PREFIXLEN}" \
         "$SW_CTN"    "$( sw_port_of proxy )" ""

add_link "$WEB1_CTN" "$WEB_IF" "${WEB1_IP}/${PREFIXLEN}" \
         "$SW_CTN"   "$( sw_port_of web1 )" ""
add_link "$WEB2_CTN" "$WEB_IF" "${WEB2_IP}/${PREFIXLEN}" \
         "$SW_CTN"   "$( sw_port_of web2 )" ""

cat <<JSON
{
  "lab": "service-failover",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
