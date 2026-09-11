#!/usr/bin/env bash
# Print the docker exec line for each machine in this lab, or open a shell on
# one when a role is named and a TTY is available.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# its menu row runs this with no argument and holds the list on screen for the
# learner to copy from.
#
# The holdout is not listed. It holds the ten files Part 3 is scored against,
# and no step in the handout leads into it.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

describe() {
    case "$1" in
        workstation) echo "the analysis box: the corpus, yara, the pev suite, and the rule file you write" ;;
        scanner)     echo "the upload endpoint: lighttpd, the CGI, and clamscan" ;;
        client)      echo "the machine that posts a file to the scanner" ;;
    esac
}

if [ $# -ge 1 ]; then
    role="$1"
    ctn="$( ctn_of "$role" )"
    if ! printf '%s\n' "${SHELL_ROLES[@]}" | grep -qx "$role"; then
        echo "unknown role '$role'. Try one of: ${SHELL_ROLES[*]}" >&2
        exit 1
    fi
    running "$ctn" || { echo "$ctn is not running; spawn the lab first" >&2; exit 1; }
    if [ -t 0 ] && [ -t 1 ]; then
        exec docker exec -it "$ctn" bash
    fi
    echo "docker exec -it $ctn bash"
    exit 0
fi

echo "Shell into a machine by pasting one of these into your own terminal:"
echo
for role in "${SHELL_ROLES[@]}"; do
    ctn="$( ctn_of "$role" )"
    state="not running"
    running "$ctn" && state="$( ip_of "$role" )"
    printf '  %-12s %-16s docker exec -it %s bash\n' "$role" "$state" "$ctn"
    printf '  %-12s %s\n\n' "" "$( describe "$role" )"
done
echo "Everything in Parts 1 to 3 is done on the workstation."
