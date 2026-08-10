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
# Nothing here is a "victim": no host in this lab is attacked in a way that harms
# it, and marking one would tell the learner where to look before they have
# scanned anything.
#
# TWO VIEWS, because this lab's subject is what an attacker does not know yet.
# Every other lab prints its full addressing in the handout, which for a lab about
# finding hosts in a /24 would print Part 1's answer on the first page. So:
#
#   SCAN_TOPO_VIEW unset (default)   the learner's view: attacker, router, and the
#                                    switch the target /24 hangs off. The hosts
#                                    inside that /24 are not drawn, because
#                                    finding them is the exercise. This is what
#                                    handout.tex \inputs as topology.tex.
#   SCAN_TOPO_VIEW=full              every host with its address, for the
#                                    instructor answer key.
#
# Re-run after any topology change (both views, or the two drift apart):
#   labs/tools/topofig.py labs/catalogue/scanning
#   SCAN_TOPO_VIEW=full labs/tools/topofig.py labs/catalogue/scanning \
#       -o labs/catalogue/scanning/solution/topology-full.tex
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

VIEW="${SCAN_TOPO_VIEW:-learner}"

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

# Pinned into a left-to-right chain (attacker, router, target network) so the
# figure reads in the direction the probes travel. Left to place them itself the
# generator hangs both leaves below the router, which reads as two peers either
# side of it rather than as one path out to a network being surveyed.
add_node "$ATTACKER_CTN" "attacker" "" 0 0
add_node "$ROUTER_CTN"   "router"   "" 8.0 0

# External edge: point-to-point, no switch. Every probe crosses this link, and
# both its addresses are known to the learner from the start.
add_link "$ATTACKER_CTN" "$ATT_IF"   "${ATTACKER_IP}/${PREFIXLEN}" \
         "$ROUTER_CTN"   "$R_EXT_IF" "${ROUTER_EXT_IP}/${PREFIXLEN}"

if [ "$VIEW" = "full" ]; then
    # Answer key: every host, every address. The three service hosts are drawn as
    # servers and the idle one as a plain host, which is the distinction the whole
    # of Part 2 turns on.
    add_node "$SW_CTN"     "switch"
    add_node "$WEB_CTN"    "server" "HTTP (80)"
    # Legend text is laid out on a fixed 3 cm pitch that topofig.py does not check
    # for overlap, so a key entry has to stay short: "FTP (21), silent to ping" ran
    # into the next swatch. The ping fact is in the answer key's own table, one
    # paragraph below this figure.
    add_node "$FTP_CTN"    "server" "FTP (21)"
    add_node "$TELNET_CTN" "server" "telnet (23)"
    add_node "$IDLE_CTN"   "host"   "no service"

    add_link "$ROUTER_CTN" "$R_TGT_IF" "${ROUTER_TGT_IP}/${PREFIXLEN}" \
             "$SW_CTN" "$( sw_port_of router )" ""
    for h in "${TARGET_HOSTS[@]}"; do
        add_link "$( ctn_of "$h" )" "$HOST_IF" "${TARGET_IP[$h]}/${PREFIXLEN}" \
                 "$SW_CTN" "$( sw_port_of "$h" )" ""
    done
else
    # Learner's view: the target network is one switch with an address range and
    # nothing drawn behind it. How many hosts are in there, which addresses they
    # hold, and what each one runs are the three things Parts 1 and 2 answer, so
    # none of them is on the figure.
    add_node "$SW_CTN" "switch" "target network" 16.0 0

    add_link "$ROUTER_CTN" "$R_TGT_IF" "${ROUTER_TGT_IP}/${PREFIXLEN}" \
             "$SW_CTN" "$( sw_port_of router )" ""
fi

cat <<JSON
{
  "lab": "scanning",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
