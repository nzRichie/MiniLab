#!/usr/bin/env bash
# Render handout.pdf from handout.tex when it is missing or stale, then open it.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

TEX="$LAB_DIR/handout.tex"
PDF="$LAB_DIR/handout.pdf"

newest_source() {
    find "$LAB_DIR" -maxdepth 1 -name '*.tex' -newer "$PDF" -print -quit 2>/dev/null
}

if [ ! -f "$PDF" ] || [ -n "$( newest_source )" ]; then
    command -v latexmk >/dev/null 2>&1 || {
        echo "latexmk not found; cannot build $PDF" >&2; exit 1; }
    echo "[handout] building $PDF"
    latexmk -pdf -interaction=nonstopmode -cd "$TEX" >/dev/null || {
        echo "latexmk failed; see $LAB_DIR/handout.log" >&2; exit 1; }
fi

if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$PDF" >/dev/null 2>&1 &
    echo "[handout] opened $PDF"
else
    echo "[handout] $PDF"
fi
