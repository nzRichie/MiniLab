#!/usr/bin/env bash
# Print the `docker exec -it` line for every node in the lab, or open a shell
# on one of them.
#
# Part 1 is worked from attacker, Parts 2A and 2B from web, and Part 2C from gw.
# The other two roles are here for a learner running a liveness check and for an
# instructor looking at where a probe ended up.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# with no terminal attached this prints one line per node and the learner pastes
# the one they want into their own terminal. Given a node name as $1 from a real
# terminal it opens that shell instead.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROLES="attacker web gw ops mon"

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

# One block per node: what it is, then the line that opens a shell on it.
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
node attacker "the outside machine (${ATTACKER_IP}); Part 1 is worked here," "and the listener runs here"
node web "the appliance (${WEB_IP}); Parts 2A and 2B are worked here"
node gw "the gateway (${GW_INSIDE_IP} inside, ${GW_OUTSIDE_IP} outside);" "Part 2C is worked here"
node ops "the operator's workstation (${OPS_IP}); the legitimate caller"
node mon "the upstream monitor (${MON_IP}); the reachability target"
