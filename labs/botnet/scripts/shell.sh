#!/usr/bin/env bash
# Print the `docker exec -it` line for every node in the lab, or open a shell on
# one of them.
#
# The lab is worked from two machines: the c2, where the controller runs and
# every task is issued, and the router, where Part 4's captures and rules go.
# The other twelve are here for a learner who wants to see the botnet from a
# host it recruited, or an instructor checking why a probe did not land.
#
# The TUI streams output non-interactively and cannot host a PTY, so with no
# terminal attached this prints one line per node and the learner pastes the one
# they want. Given a node name as $1 from a real terminal it opens that shell.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROLES="router server admin host1 host2 host3 host4 host5 host6 c2 loader"

running="$( docker ps --format '{{.Names}}' 2>/dev/null )"
state_of() { grep -qxF "$1" <<< "$running" || echo "   (not running)"; }

ctn_width=0
for role in $ROLES; do
    ctn="$( ctn_of "$role" )"
    [ ${#ctn} -gt "$ctn_width" ] && ctn_width=${#ctn}
done

if [ $# -ge 1 ]; then
    role="$1"
    case " $ROLES " in
        *" $role "*) ;;
        *) echo "unknown node '$role'; expected one of: $ROLES" >&2; exit 1 ;;
    esac
    ctn="$( ctn_of "$role" )"
    if [ -t 0 ] && [ -t 1 ]; then exec docker exec -it "$ctn" bash; fi
    echo "Open a terminal and run:"
    echo "    docker exec -it $ctn bash"
    exit 0
fi

node() {   # <role> <description line>...
    local role="$1"; shift
    local ctn; ctn="$( ctn_of "$role" )"
    printf '  %-7s %s\n' "$role" "$1"; shift
    local extra
    for extra in "$@"; do printf '  %-7s %s\n' "" "$extra"; done
    printf '  %-7s docker exec -it %-*s bash%s\n\n' \
        "" "$ctn_width" "$ctn" "$( state_of "$ctn" )"
}

echo "Open a terminal and run the line for the node you want."
echo
node c2     "the controller ($C2_IP). Run 'c2' here to open the console; this" "is where you install bots and issue tasks. One of the two machines" "you need"
node router "the router ($R_INSIDE_IP inside, $R_FIELD_IP field, $R_OP_IP operator)." "Every packet between legs crosses it; Part 4's captures and rules" "go here"
node server "the inside server ($SERVER_IP): web on tcp/80, ssh on tcp/22"
node admin  "the site's admin workstation ($ADMIN_IP); runs no service"
node host1  "field host ($HOST1_IP)"
node host2  "field host ($HOST2_IP)"
node host3  "field host ($HOST3_IP)"
node host4  "field host ($HOST4_IP)"
node host5  "field host ($HOST5_IP)"
node host6  "field host ($HOST6_IP)"
node loader "the payload host ($LOADER_IP): serves bot.py and the wordlist"
