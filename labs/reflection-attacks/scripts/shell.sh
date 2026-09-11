#!/usr/bin/env bash
# Print the `docker exec -it` line for every node in the lab, or open a shell
# on one of them.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# with no terminal attached this prints one line per node and the learner pastes
# the one they want into their own terminal. Given a node name as $1 from a real
# terminal it opens that shell instead.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROLES="attacker router victim dns ntp"

running="$( docker ps --format '{{.Names}}' 2>/dev/null )"

# Marks the nodes whose container is not up, so a learner who has not spawned
# the lab (or has torn it down) reads why the line they are about to paste fails.
state_of() {   # <container>
    grep -qxF "$1" <<< "$running" || echo "   (not running)"
}

# The container names share a prefix and differ only in the node name, so the
# widest of them is what the commands line up on.
ctn_width=0
for role in $ROLES; do
    ctn="$( ctn_of "$role" )"
    if [ ${#ctn} -gt "$ctn_width" ]; then ctn_width=${#ctn}; fi
done

if [ $# -ge 1 ]; then
    role="$1"
    case " $ROLES " in
        *" $role "*) ;;
        *) echo "unknown node '$role'; expected one of: $ROLES" >&2; exit 1 ;;
    esac
    ctn="$( ctn_of "$role" )"
    if [ -t 0 ] && [ -t 1 ]; then
        exec docker exec -it "$ctn" bash
    fi
    echo "Open a terminal and run:"
    echo "    docker exec -it $ctn bash"
    exit 0
fi

echo "Open a terminal and run the line for the node you want."
echo
for role in $ROLES; do
    ctn="$( ctn_of "$role" )"
    printf '  %-10s docker exec -it %-*s bash%s\n' \
        "$role" "$ctn_width" "$ctn" "$( state_of "$ctn" )"
done
