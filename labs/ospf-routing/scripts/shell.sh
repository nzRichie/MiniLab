#!/usr/bin/env bash
# Print the command that opens a shell on every node in the lab, or open one of
# them. The routers are configured only over vtysh, so a router line runs vtysh
# and a host line runs bash.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# with no terminal attached this prints one line per node and the learner pastes
# the one they want into their own terminal. Given a node name as $1 from a real
# terminal it opens that shell instead.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROUTERS="lond pari trga newy zuri"
HOSTS="lond-host pari-host trga-host newy-host zuri-host"
ROLES="$ROUTERS $HOSTS"

running="$( docker ps --format '{{.Names}}' 2>/dev/null )"

# Marks the nodes whose container is not up, so a learner who has not spawned
# the lab (or has torn it down) reads why the line they are about to paste fails.
state_of() {   # <container>
    grep -qxF "$1" <<< "$running" || echo "   (not running)"
}

# <node> -> the container it lives in, and the command a shell on it runs.
resolve() {
    case "$1" in
        lond|pari|trga|newy|zuri)
            ctn="$( router_ctn "$1" )"; cmd=vtysh ;;
        lond-host|pari-host|trga-host|newy-host|zuri-host)
            ctn="$( host_ctn "${1%-host}" )"; cmd=bash ;;
        *)
            return 1 ;;
    esac
}

if [ $# -ge 1 ]; then
    resolve "$1" || {
        echo "unknown node '$1'; expected one of: $ROLES" >&2
        exit 1
    }
    if [ -t 0 ] && [ -t 1 ]; then
        exec docker exec -it "$ctn" "$cmd"
    fi
    echo "Open a terminal and run:"
    echo "    docker exec -it $ctn $cmd"
    exit 0
fi

# The container names share a prefix and differ only in the node name, so the
# widest of them is what the commands line up on.
ctn_width=0
for role in $ROLES; do
    resolve "$role"
    if [ ${#ctn} -gt "$ctn_width" ]; then ctn_width=${#ctn}; fi
done

echo "Open a terminal and run the line for the node you want."
echo
echo "  routers (vtysh; every OSPF command in the handout is typed here)"
for role in $ROUTERS; do
    resolve "$role"
    printf '    %-11s docker exec -it %-*s %s%s\n' \
        "$role" "$ctn_width" "$ctn" "$cmd" "$( state_of "$ctn" )"
done
echo
echo "  hosts (a plain shell, for ping and traceroute)"
for role in $HOSTS; do
    resolve "$role"
    printf '    %-11s docker exec -it %-*s %s%s\n' \
        "$role" "$ctn_width" "$ctn" "$cmd" "$( state_of "$ctn" )"
done
