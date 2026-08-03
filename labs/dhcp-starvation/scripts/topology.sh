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
# The server is drawn as a server because that is the role it plays: it is the
# only host that answers DHCP, and the identity the attacker takes over. The
# victim carries no fixed address, so its end of the link is labelled with where
# the address comes from rather than with a number. The switch ports are Layer 2
# and hold no address, so their a_ip/b_ip list is empty and the figure labels
# that end with the port name.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/dhcp-starvation
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

PFX="${SUBNET##*/}"

# The hosts' link labels, keyed by the role name spawn.sh wires. The victim's is
# not an address: it leases one out of LEGIT_POOL_LO-LEGIT_POOL_HI, and which
# address it holds changes every time it asks with a new MAC.
declare -A HOST_LABEL=(
    [server]="${SERVER_IP}/${PFX}"
    [attacker]="${ATTACKER_IP}/${PFX}"
    [victim]="leased via DHCP"
)

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
add_link() {   # <a_ctn> <a_if> <a_label> <b_ctn> <b_if> <b_label>   ("" for none)
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips "$3" )" "$4" "$5" "$( json_ips "$6" )" )" )
}
json_ips() {   # quote each label; an empty argument means an unnumbered interface
    local out="" ip
    for ip in "$@"; do [ -n "$ip" ] && out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}

add_node "$ATTACKER_CTN" "attacker"
add_node "$SW_CTN"       "switch"
add_node "$VICTIM_CTN"   "victim"
add_node "$SERVER_CTN"   "server" "DHCP server"

# One flat broadcast domain: every host hangs off S1 by a veth pair, host side
# named after the switch, switch side named after the host (spawn.sh). The
# server's port is the one DHCP snooping trusts in Part 2.
for h in "${HOSTS[@]}"; do
    add_link "$( ctn_of "$h" )" "$HOST_IF" "${HOST_LABEL[$h]}" \
             "$SW_CTN" "${AS}-${h}" ""
done

cat <<JSON
{
  "lab": "dhcp-starvation",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
