#!/usr/bin/env bash
# Print this lab's topology as JSON, for labs/tools/topofig.py to draw.
#
# Everything comes from lib.sh, so the figure and the lab the learner spawns
# cannot disagree. Nothing here touches Docker: it reads the lab's definitions
# and prints, so it runs on a machine that has never spawned this lab.
#
# The portal is drawn as the victim, because it is the host every file in Part 1
# is read from. The database is a server: it holds the table the disclosed
# credential reaches and it is where stages 2C and 2D are worked. The reports
# host is a plain host, which is what it is: it runs one job, holds no data and
# is never attacked.
#
# Re-run after any topology change:  labs/tools/topofig.py labs/catalogue/path-traversal
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

nodes=() links=()
join_lines() {
    printf '%s' "$1"; shift
    local x
    for x in "$@"; do printf ',\n%s' "$x"; done
    printf '\n'
}
add_node_at() {   # <name> <type> <legend> <x> <y>
    nodes+=( "$( printf '    {"name": "%s", "type": "%s", "legend": "%s", "at": [%s, %s]}' "$1" "$2" "$3" "$4" "$5" )" )
}
add_link() {   # <a_ctn> <a_if> <a_ips> <b_ctn> <b_if> <b_ips>
    links+=( "$( printf '    {"a": "%s", "a_if": "%s", "a_ip": [%s], "b": "%s", "b_if": "%s", "b_ip": [%s]}' \
        "$1" "$2" "$( json_ips $3 )" "$4" "$5" "$( json_ips $6 )" )" )
}
json_ips() {
    local out="" ip
    for ip in "$@"; do out="${out:+$out, }\"$ip\""; done
    printf '%s' "$out"
}

add_node_at "$WEB_CTN"      "victim"   "portal"       0    3
add_node_at "$DB_CTN"       "server"   "database"     0    0
add_node_at "$REPORTS_CTN"  "host"     "reports job"  0   -3
add_node_at "$SW_CTN"       "switch"   "switch"       6    0
add_node_at "$ATTACKER_CTN" "attacker" "attacker"    12    0

for h in "${HOSTS[@]}"; do
    add_link "$( ctn_of "$h" )" "$LAN_IF" "$( ip_of "$h" )/${PREFIXLEN}" \
             "$SW_CTN" "$( sw_port_of "$h" )" ""
done

cat <<JSON
{
  "lab": "path-traversal",
  "nodes": [
$( join_lines "${nodes[@]}" )
  ],
  "links": [
$( join_lines "${links[@]}" )
  ]
}
JSON
