#!/usr/bin/env bash
# Print the `docker exec -it` line for every node in the lab, or open a shell
# on one of them.
#
# Two of the five are used throughout: the server, where every rule in the lab
# is written and both log tails are read, and the attacker, where every probe is
# sent from. The handout asks for two terminals on the server at once, one for
# the rules and one for the tail, and both come from the same line.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# with no terminal attached this prints one line per node and the learner pastes
# the one they want into their own terminal. Given a node name as $1 from a real
# terminal it opens that shell instead.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROLES="server client attacker customer router"

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
    printf '  %-9s %s\n' "$role" "$1"; shift
    local extra
    for extra in "$@"; do
        printf '  %-9s %s\n' "" "$extra"
    done
    printf '  %-9s docker exec -it %-*s bash%s\n\n' \
        "" "$ctn_width" "$ctn" "$( state_of "$ctn" )"
}

echo "Open a terminal and run the line for the node you want."
echo "The lab needs two terminals on the server at once: one for the rules, one"
echo "for the log tail. Both come from the server line."
echo
node server   "the machine under attack ($SERVER_IP). Every rule in this lab is" \
              "written here, and both log tails are read here"
node attacker "the outside machine ($ATTACKER_IP, and $ATTACKER_ALT_IP on the" \
              "second outside prefix). Every probe is sent from here"
node client   "the internal workstation ($CLIENT_IP). Its telnet access has to" \
              "survive every rule you write"
node customer "the outside reader of the web site ($CUSTOMER_IP). It is how you" \
              "check a rule aimed at telnet stayed aimed at telnet"
node router   "the router ($RTR_INSIDE_IP inside, $RTR_OUTSIDE_IP outside). It" \
              "forwards and filters nothing; you do not need it"
