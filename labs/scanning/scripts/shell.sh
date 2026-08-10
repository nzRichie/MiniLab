#!/usr/bin/env bash
# Shell into a lab node.  Usage: shell.sh [attacker|router|host1|host2|host3|host4]
# (default attacker). The four target hosts are named for their number and not for
# the service each runs, because this list is on the TUI's node picker and finding
# out what runs where is the graded exercise.
# The current miniManager engine streams non-interactively and cannot host a live
# shell, so when there is no TTY we print the command for the learner to run in
# their own terminal (proposal: interactive Session is a later enhancement).
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

role="${1:-attacker}"
ctn="$(ctn_of "$role")"

if [ -t 0 ] && [ -t 1 ]; then
    exec docker exec -it "$ctn" bash
else
    echo "Open a terminal and run:"
    echo "    docker exec -it $ctn bash"
fi
