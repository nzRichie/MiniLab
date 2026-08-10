#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Every name, address and VLAN id comes from lib.sh, so the handout's figure and
# the lab the learner spawns cannot disagree. Nothing here touches Docker: it
# reads the lab's definitions and prints, so it runs on a machine that has never
# spawned this lab, and in a clean checkout.
#
# Node types (topofig.py fixes the shape and colour of each): router, switch,
# attacker, victim, server, host. The peer is a plain `host`: it is a bystander,
# not a role the attack is about, and the key calls it what it is to the lab.
#
# Two switches, not one, because the hop needs a switch boundary to cross. The
# link between them is the 802.1Q trunk, and its native VLAN is the setting the
# whole lab turns on, so the figure labels the trunk with it rather than with two
# port names a reader learns nothing from. The host-side ends carry the address
# and VLAN; the switch-side ends carry the OVS port name the handout types.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/vlan-hopping
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

# The host-side link labels, keyed by the role spawn.sh wires. Each names the
# address and the VLAN its access port puts it in, because "which VLAN" is the
# one thing a reader needs from this figure.
declare -A HOST_LABEL=(
    [attacker]="${ATTACKER_IP}/${PREFIXLEN} VLAN ${VLAN_ATT}"
    [peer]="${PEER_IP}/${PREFIXLEN} VLAN ${VLAN_ATT}"
    [victim]="${VICTIM_IP}/${PREFIXLEN} VLAN ${VLAN_VICTIM}"
)

nodes=() links=()
join_lines() {   # the accumulated objects, comma-separated, one per line
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
add_link() {   # <a_ctn> <a_if> <a_label> <b_ctn> <b_if> <b_label>   ("" for none)
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips "$3" )" "$4" "$5" "$( json_ips "$6" )" )" )
}
json_ips() {   # quote each label; an empty argument means an unlabelled interface
    local out="" ip
    for ip in "$@"; do [ -n "$ip" ] && out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}

# The two switches are pinned side by side so the drawing runs left to right in
# the order the frame travels: attacker, S1, trunk, S2, the two hosts behind it.
# Left to itself the layout stacks the switches vertically and the trunk, the one
# link the lab is about, reads as an aside rather than as the spine. Everything
# else stays automatic.
add_node "$ATTACKER_CTN" "attacker" ""              0  0
add_node "$SW1_CTN"      "switch"   ""              6  0
add_node "$SW2_CTN"      "switch"   ""             12  0
add_node "$PEER_CTN"     "host"     "honest peer"  18  2.5
add_node "$VICTIM_CTN"   "victim"   ""             18 -2.5

# Each host hangs off its own switch by a veth pair: host side named after the
# switch (<AS>-<SW>), switch side named after the host (<AS>-<host>).
for h in "${HOSTS[@]}"; do
    add_link "$( ctn_of "$h" )" "$( host_if_of "$h" )" "${HOST_LABEL[$h]}" \
             "$( ctn_of "$( sw_of "$h" )" )" "$( sw_port_of "$h" )" ""
done

# The trunk. Labelled with what it carries and which VLAN it carries untagged,
# because that equality is the vulnerability the lab exploits.
add_link "$SW1_CTN" "$S1_TRUNK_PORT" "trunk VLAN ${VLAN_ATT}+${VLAN_VICTIM}" \
         "$SW2_CTN" "$S2_TRUNK_PORT" "native VLAN ${NATIVE_VLAN_BAD}"

cat <<JSON
{
  "lab": "vlan-hopping",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
