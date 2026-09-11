#!/usr/bin/env bash
# Print the `docker exec -it` line for every node in the lab, or open a shell
# on one of them.
#
# Part 1 is worked from two terminals at once: the appliance, where the source
# is read and the offset is measured under a debugger, and the attacker, where
# the request is built and sent. Part 2 is worked on the appliance, because that
# is where the compiler is.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# with no terminal attached this prints one line per node and the learner pastes
# the one they want into their own terminal. Given a node name as $1 from a real
# terminal it opens that shell instead. gdb needs a terminal, so the appliance's
# line is one a learner will use.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROLES="svc attacker ops"

running_list="$( docker ps --format '{{.Names}}' 2>/dev/null )"

state_of() {   # <container>
    grep -qxF "$1" <<< "$running_list" || echo "   (not running)"
}

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

node() {   # <role> <description line>...
    local role="$1"; shift
    local ctn; ctn="$( ctn_of "$role" )"
    printf '  %-11s %s\n' "$role" "$1"; shift
    local extra
    for extra in "$@"; do
        printf '  %-11s %s\n' "" "$extra"
    done
    printf '  %-11s docker exec -it %-*s bash%s\n\n' \
        "" "$ctn_width" "$ctn" "$( state_of "$ctn" )"
}

echo "Open a terminal and run the line for the node you want."
echo
node svc "the appliance (${SVC_IP}); the source, the debugger and the" \
         "compiler are here, and every Part 2 build is made here"
node attacker "the attacker's machine (${ATTACKER_IP}); every request in" \
              "Part 1 and every re-run in Part 2 is sent from here"
node ops "the operator's workstation (${OPS_IP}); the legitimate caller"
