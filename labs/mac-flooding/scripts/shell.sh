#!/usr/bin/env bash
# Shell into a lab node.  Usage: shell.sh [attacker|victim|gateway|staff|S1|S2]  (default attacker)
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
