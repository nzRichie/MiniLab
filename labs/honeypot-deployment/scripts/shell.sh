#!/usr/bin/env bash
# Open a shell on one of the lab's nodes, or print the command that does.
#
# The TUI streams job output non-interactively and cannot host a PTY, so when
# there is no TTY this prints the `docker exec -it` line for the learner to run
# in their own terminal instead of trying to attach.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROLES="attacker prod honeypot admin router"

role="${1:-}"
if [ -z "$role" ]; then
    echo "usage: $( basename "$0" ) <node>" >&2
    echo "nodes: $ROLES" >&2
    exit 1
fi

case " $ROLES " in
    *" $role "*) ;;
    *) echo "unknown node '$role'; expected one of: $ROLES" >&2; exit 1 ;;
esac

ctn="$( ctn_of "$role" )"

if ! docker ps --format '{{.Names}}' | grep -qx "$ctn"; then
    echo "$ctn is not running; spawn the lab first" >&2
    exit 1
fi

if [ -t 0 ] && [ -t 1 ]; then
    exec docker exec -it "$ctn" bash
fi

echo "Run this in your own terminal:"
echo
echo "    docker exec -it $ctn bash"
echo
if [ "$role" = "honeypot" ]; then
    echo "Cowrie runs as the unprivileged 'cowrie' account, out of $COWRIE_HOME."
    echo "To work as that account instead:"
    echo
    echo "    docker exec -it -u $COWRIE_USER -w $COWRIE_HOME $ctn bash"
    echo
fi
