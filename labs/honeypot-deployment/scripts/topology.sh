#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs in a clean checkout.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/honeypot-deployment
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

# Four point-to-point links, all of them meeting at the router. The router is the
# only device that sees traffic between two segments, which is why it is the only
# device the learner configures.
#
# The production host is drawn as the victim: it is what the lab exists to keep
# untouched. The honeypot is drawn as a server because it serves the lab's
# protocol, and the admin station stays a plain host, because it has no role in
# the attack beyond having to keep working.
add_node "$ATTACKER_CTN" "attacker"
add_node "$ROUTER_CTN"   "router"
add_node "$PROD_CTN"     "victim"  "production host"
add_node "$HONEY_CTN"    "server"  "honeypot"
add_node "$ADMIN_CTN"    "host"    "management station"

add_link "$ATTACKER_CTN" "$ATT_IF"     "${ATTACKER_IP}/${PREFIXLEN}" \
         "$ROUTER_CTN"   "$R_EXT_IF"   "${ROUTER_EXT_IP}/${PREFIXLEN}"
add_link "$ROUTER_CTN"   "$R_PROD_IF"  "${ROUTER_PROD_IP}/${PREFIXLEN}" \
         "$PROD_CTN"     "$PROD_IF"    "${PROD_IP}/${PREFIXLEN}"
add_link "$ROUTER_CTN"   "$R_HONEY_IF" "${ROUTER_HONEY_IP}/${PREFIXLEN}" \
         "$HONEY_CTN"    "$HONEY_IF"   "${HONEY_IP}/${PREFIXLEN}"
add_link "$ROUTER_CTN"   "$R_MGMT_IF"  "${ROUTER_MGMT_IP}/${PREFIXLEN}" \
         "$ADMIN_CTN"    "$ADMIN_IF"   "${ADMIN_IP}/${PREFIXLEN}"

cat <<JSON
{
  "lab": "honeypot-deployment",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
