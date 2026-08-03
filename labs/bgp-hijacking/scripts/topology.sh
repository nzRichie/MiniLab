#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Every name and address comes from lib.sh, so the handout's figure and the lab
# the learner spawns cannot disagree. Nothing here touches Docker: it reads the
# lab's definitions and prints, so it runs on a machine that has never spawned
# this lab, and in a clean checkout.
#
# Node types (topofig.py fixes the shape and colour of each): router, switch,
# attacker, victim, server, host. "legend" overrides the key text for a node.
# An interface may carry more than one address: a_ip/b_ip accepts a list, and the
# AS6 host uses it for the impostor secondary it stands up inside the victim's
# block.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/bgp-hijacking
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

# The lab's roles map onto the figure's node types: AS1's host is the hijack's
# victim, AS6's is the attacker, and the rest are plain clients.
node_type() {
    case "${AS_ROLE[$1]}" in
        victim)   echo "victim" ;;
        attacker) echo "attacker" ;;
        *)        echo "host" ;;
    esac
}

nodes=() links=()
join_lines() {   # "$@" as one comma-separated object per line
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
add_link() {   # <a_ctn> <a_if> <a_ips> <b_ctn> <b_if> <b_ips>   (ips: space-separated)
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips $3 )" "$4" "$5" "$( json_ips $6 )" )" )
}
json_ips() {   # quote each address; no arguments means an unnumbered interface
    local out="" ip
    for ip in "$@"; do out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}

for as in "${ASES[@]}"; do
    add_node "$( router_ctn "$as" )" "router"
    add_node "$( host_ctn "$as" )" "$( node_type "$as" )" \
             "$( [ "${AS_ROLE[$as]}" = "client" ] && echo "client host" || true )"
done

# The RPKI plane. Both serve the lab's second protocol, so they are "server" nodes
# rather than plain hosts. They sit outside the BGP topology: the RIR is reached
# through a private management bridge that carries no lab traffic, which is why the
# only line drawn to either of them is the RTR link from a validating router.
#
# Both are pinned. Left to the automatic layout the RIR has only one neighbour and
# gets pushed a long way out to the left, which stretches the figure sideways and
# shrinks every label. Stacking the pair on the left, level with the AS3-to-AS5
# span they attach to, keeps the drawing the shape of the network: the BGP
# topology reads top to bottom, and the RPKI plane sits beside it.
# Legend text is kept to about the length of "client host": the key lays its
# entries out in one row and does not reflow, so a longer label runs into the
# next swatch. What each container actually runs is in the handout, not the key.
add_node "$RIR_CTN"       "server" "RIR (Krill)" -6.5 -12.7
add_node "$VALIDATOR_CTN" "server" "validator"   -6.5 -9.5

# Inter-AS links: eBGP over a /30, router a's interface toward b named to_as<b>.
for link in "${LINKS[@]}"; do
    read -r a b a_ip b_ip subnet <<<"$link"
    pfx="${subnet##*/}"
    add_link "$( router_ctn "$a" )" "$( peer_if "$b" )" "${a_ip}/${pfx}" \
             "$( router_ctn "$b" )" "$( peer_if "$a" )" "${b_ip}/${pfx}"
done

# Host links: each router to its own host. AS6's host carries a second address,
# the impostor inside the victim's block, so its label lists both.
for as in "${ASES[@]}"; do
    host_ips="${AS_HOST_IP[$as]}/24"
    router_ips="${AS_GW[$as]}/24"
    if [ "$as" -eq "$ATTACKER_AS" ]; then
        host_ips="$host_ips ${IMPOSTOR_HOST_IP}/${IMPOSTOR_SUBNET##*/}"
        router_ips="$router_ips ${IMPOSTOR_GW}/${IMPOSTOR_SUBNET##*/}"
    fi
    add_link "$( router_ctn "$as" )" "$HOST_IF_ROUTER" "$router_ips" \
             "$( host_ctn "$as" )"   "$HOST_IF_HOST"   "$host_ips"
done

# RTR links: each validating router to the validator. These carry RPKI-to-Router
# only and are never announced into BGP.
for link in "${RPKI_LINKS[@]}"; do
    read -r as vip rip subnet <<<"$link"
    pfx="${subnet##*/}"
    add_link "$VALIDATOR_CTN"      "$( rpki_if_validator "$as" )" "${vip}/${pfx}" \
             "$( router_ctn "$as" )" "$( rpki_if_router )"        "${rip}/${pfx}"
done

# The validator fetches the RIR's repository over a private docker bridge rather
# than a veth, so that Krill's web portal can be published to the host. It is drawn
# as an unnumbered link because neither end is addressed by this lab.
add_link "$VALIDATOR_CTN" "rrdp" "" "$RIR_CTN" "rrdp" ""

cat <<JSON
{
  "lab": "bgp-hijacking",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
