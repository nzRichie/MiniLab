#!/usr/bin/env bash
# Every sandbox, with what it holds and whether it is running.
#
# This row carries the explanation the Spawn prompt cannot: the engine gives a
# prompt 22 characters of inner width at 80 columns, so "Which sandbox? (name as
# shown by List sandboxes)" renders as "Which sandbox? (name a". The prompt says
# "Sandbox name?" and this says what the names are.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ensure_home

shopt -s nullglob
found=0
printf '%-22s %-22s %-6s %-6s %s\n' NAME PROJECT NODES LINKS STATE
for d in "$SANDBOX_ROOT"/*/; do
    [ -f "$d/topology.toml" ] || continue
    found=$(( found + 1 ))
    name="$( basename "$d" )"

    nodes=$( grep -c '^\[\[nodes\]\]' "$d/topology.toml" 2>/dev/null || echo 0 )
    links=$( grep -c '^\[\[links\]\]' "$d/topology.toml" 2>/dev/null || echo 0 )

    # The containers are labelled with the PROJECT name, which is not always the
    # directory name. Filtering on the directory reports a running sandbox as
    # stopped.
    project="$( project_name_of "$d" )"
    [ -n "$project" ] || project="$name"

    if [ ! -f "$d/scripts/spawn.sh" ]; then
        state="not emitted"
    elif docker info >/dev/null 2>&1; then
        up=$( docker ps -q --filter "label=minilabs.sandbox=$project" | wc -l )
        if [ "$up" -gt 0 ]; then
            state="running ($up)"
        else
            state="stopped"
        fi
    else
        state="unknown"
    fi
    printf '%-22s %-22s %-6s %-6s %s\n' "$name" "$project" "$nodes" "$links" "$state"
done

if [ "$found" -eq 0 ]; then
    echo
    echo "No sandboxes yet. They live in $SANDBOX_ROOT."
    echo "Start the editor and draw one, or build one on the command line:"
    echo "    $MINICREATE new $SANDBOX_ROOT/my-lab --name my-lab"
fi
