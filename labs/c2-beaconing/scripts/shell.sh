#!/usr/bin/env bash
# Print the `docker exec -it` line for every node in the lab, or open a shell
# on one of them.
#
# The lab is worked entirely from the gateway. The other five roles are here for
# an instructor looking at how the traffic is produced, and for a learner who
# wants to see a service from the machine that runs it after the exercise is
# over. Opening a shell on a workstation and reading its process list answers
# Part 2 without measuring anything, which is worth knowing and is not the
# exercise.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# with no terminal attached this prints one line per node and the learner pastes
# the one they want into their own terminal. Given a node name as $1 from a real
# terminal it opens that shell instead.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROLES="gw ws1 ws2 ws3 ext1 ext2"

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
    printf '  %-6s %s\n' "$role" "$1"; shift
    local extra
    for extra in "$@"; do
        printf '  %-6s %s\n' "" "$extra"
    done
    printf '  %-6s docker exec -it %-*s bash%s\n\n' \
        "" "$ctn_width" "$ctn" "$( state_of "$ctn" )"
}

echo "Open a terminal and run the line for the node you want."
echo
node gw "the gateway ($GW_INSIDE_IP inside, $GW_OUTSIDE_IP outside). Every" "packet between the two segments crosses it; this is where the lab" "is worked, and the only machine you need"
node ws1 "workstation ($WS1_IP)"
node ws2 "workstation ($WS2_IP)"
node ws3 "workstation ($WS3_IP)"
node ext1 "outside host, two addresses on the ${OUTSIDE_SUBNET} segment"
node ext2 "outside host, two addresses on the ${OUTSIDE_SUBNET} segment"
