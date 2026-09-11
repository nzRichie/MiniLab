#!/usr/bin/env bash
# Render handout.pdf from handout.tex when the PDF is missing or older than any
# of its sources, then open it.
#
# topology.tex is a source here and is treated as one, but it cannot be
# REGENERATED here: labs/tools/topofig.py is an authoring tool and is not shipped
# in the release tree. When the topology changes, regenerate the figure by hand
# in the same commit as the change that made it stale.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

cd "$LAB_DIR"

needs_build=no
if [ ! -f handout.pdf ]; then
    needs_build=yes
else
    for src in handout.tex tui.tex topology.tex; do
        [ -f "$src" ] || continue
        [ "$src" -nt handout.pdf ] && needs_build=yes
    done
fi

if [ "$needs_build" = yes ]; then
    command -v latexmk >/dev/null 2>&1 || {
        echo "handout.pdf is missing or out of date and latexmk is not installed." >&2
        echo "Install a TeX distribution, or read handout.tex directly." >&2
        exit 1
    }
    echo "[handout] building handout.pdf"
    latexmk -pdf -interaction=nonstopmode -halt-on-error -cd handout.tex >/dev/null
fi

echo "[handout] $LAB_DIR/handout.pdf"
for opener in xdg-open open; do
    if command -v "$opener" >/dev/null 2>&1; then
        "$opener" handout.pdf >/dev/null 2>&1 &
        exit 0
    fi
done
echo "[handout] no opener found; open the path above by hand"
