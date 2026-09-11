#!/usr/bin/env bash
# Print the `docker exec -it` line for every node in the lab, or open a shell
# on one of them.
#
# Part 1 is worked from attacker. Part 2's first two stages are worked on web
# and its last two on db, and reports is where the check that catches stage 2C's
# wrong answer is run.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# with no terminal attached this prints one line per node and the learner pastes
# the one they want into their own terminal. Given a node name as $1 from a real
# terminal it opens that shell instead.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROLES="attacker web db reports"

running_names="$( docker ps --format '{{.Names}}' 2>/dev/null )"

# Marks the nodes whose container is not up, so a learner who has not spawned
# the lab (or has torn it down) reads why the line they are about to paste fails.
state_of() {   # <container>
    grep -qxF "$1" <<< "$running_names" || echo "   (not running)"
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
node attacker "your own machine (${ATTACKER_IP}); every request in Part 1 is sent" "from here, and so is the database session at the end of it"
node web "the portal (${WEB_IP}); stages 2A and 2B are worked here, and" "the source of the viewer is at ${VIEW_FILE}"
node db "the database (${DB_IP}); stages 2C and 2D are worked here"
node reports "the reports host (${REPORTS_IP}); run ${REPORT_CMD} here" "to see whether the nightly job can still reach the database"
