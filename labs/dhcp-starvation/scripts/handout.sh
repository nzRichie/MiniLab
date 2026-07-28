#!/usr/bin/env bash
# Render (with latexmk) and open the lab handout. The authored source is
# handout.tex; this builds handout.pdf when the PDF is missing or older than the
# source, then points the learner at the PDF. The TUI does not render it itself.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

tex="$LAB_DIR/handout.tex"
pdf="$LAB_DIR/handout.pdf"

if [ ! -f "$pdf" ] || [ "$tex" -nt "$pdf" ]; then
    if command -v latexmk >/dev/null 2>&1; then
        echo "Rendering handout.pdf from handout.tex ..."
        if latexmk -pdf -interaction=nonstopmode -cd "$tex" >/dev/null 2>&1; then
            latexmk -c -cd "$tex" >/dev/null 2>&1   # drop build artifacts, keep the PDF
        else
            echo "latexmk failed; falling back to the .tex source."
        fi
    else
        echo "latexmk not found; falling back to the .tex source."
    fi
fi

if [ -f "$pdf" ]; then
    target="$pdf"
    echo "Handout: $pdf"
else
    target="$tex"
    echo "Handout source: $tex"
fi

if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$target" >/dev/null 2>&1 &
fi
