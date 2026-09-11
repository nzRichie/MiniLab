#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs in a clean checkout.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/dns-poisoning
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

# One switched campus segment and two point-to-point links, meeting at the router.
# The two links are what makes the attack an off-path one: nothing the attacker
# sends or receives crosses the resolver-to-authoritative link, so it never sees
# the query it is trying to answer.
#
# Key text is laid out on a fixed pitch that topofig.py does not check for overlap,
# so each legend stays short: "authoritative for uni.lab" ran into the entry beside
# it. What each server is authoritative for is in the addressing table below the
# figure, one paragraph away.
#
# The resolver is drawn as the victim because it is the machine the attack acts
# on: the poison lands in its cache, and it is the machine the learner hardens.
# The campus host that believes it is a plain host, because it holds no defence
# and runs no service. Both name servers are servers.
add_node "$ATTACKER_CTN" "attacker"
add_node "$ROUTER_CTN"   "router"
add_node "$SW_CTN"       "switch"
add_node "$RESOLVER_CTN" "victim"  "resolver"
add_node "$VICTIM_CTN"   "host"    "campus host"
add_node "$AUTH_CTN"     "server"  "uni.lab server"

add_link "$ROUTER_CTN"   "$R_HOSTILE_IF" "${ROUTER_HOSTILE_IP}/${PREFIXLEN}" \
         "$ATTACKER_CTN" "$EXT_IF"       "${ATTACKER_IP}/${PREFIXLEN}"
add_link "$ROUTER_CTN"   "$R_AUTH_IF"    "${ROUTER_AUTH_IP}/${PREFIXLEN}" \
         "$AUTH_CTN"     "$EXT_IF"       "${AUTH_IP}/${PREFIXLEN}"
add_link "$ROUTER_CTN"   "$R_CAMPUS_IF"  "${ROUTER_CAMPUS_IP}/${PREFIXLEN}" \
         "$SW_CTN"       "$( sw_port_of router )" ""
add_link "$RESOLVER_CTN" "$HOST_IF"      "${RESOLVER_IP}/${PREFIXLEN}" \
         "$SW_CTN"       "$( sw_port_of resolver )" ""
add_link "$VICTIM_CTN"   "$HOST_IF"      "${VICTIM_IP}/${PREFIXLEN}" \
         "$SW_CTN"       "$( sw_port_of victim )" ""

cat <<JSON
{
  "lab": "dns-poisoning",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
