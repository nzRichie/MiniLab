#!/usr/bin/env bash
# Print the command that opens a shell on a range node, or open one.
#
# Both the host count and the router count are drawn at spawn, so the node list
# is whatever containers are up rather than a fixed set. It is also held back
# until Score has run: naming the nodes names one container per machine, and how
# many machines are out there is one of the things you are scored on. Before
# then the only node listed is attacker, which is where every step of the
# exercise runs.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# with no terminal attached this prints the line for the learner to paste into
# their own terminal. Given a node name as $1 from a real terminal it opens that
# shell instead.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

# The nodes of the range that is up, helper container excluded.
nodes() {
    docker ps --format '{{.Names}}' 2>/dev/null \
        | grep "^${CTN_PREFIX}" \
        | sed "s/^${CTN_PREFIX}//" \
        | grep -v '^netadmin_helper$' \
        | sort
}

if [ $# -ge 1 ]; then
    role="$1"
    ctn="$( ctn_of "$role" )"
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qxF "$ctn"; then
        echo "No container named $ctn is running."
        echo "Run Status to see which node tokens this range accepts."
        exit 1
    fi
    if [ -t 0 ] && [ -t 1 ]; then
        exec docker exec -it "$ctn" bash
    fi
    echo "Open a terminal and run:"
    echo "    docker exec -it $ctn bash"
    exit 0
fi

listed="$( nodes )"
if [ -z "$listed" ]; then
    echo "No range is running. Spawn one first."
    exit 0
fi

if [ ! -f "$SCORED_MARKER" ]; then
    listed="attacker"
fi

echo "Open a terminal and run the line for the node you want."
echo
ctn_width=0
for role in $listed; do
    ctn="$( ctn_of "$role" )"
    if [ ${#ctn} -gt "$ctn_width" ]; then ctn_width=${#ctn}; fi
done
for role in $listed; do
    printf '  %-10s docker exec -it %-*s bash\n' "$role" "$ctn_width" "$( ctn_of "$role" )"
done
echo

if [ -f "$SCORED_MARKER" ]; then
    echo "Every step of the exercise runs on attacker. The rest are for looking at"
    echo "why a probe did not land."
else
    echo "The rest are listed once you have run Score. Naming them names one"
    echo "container per machine, and how many machines are out there is one of the"
    echo "things you are scored on."
fi
