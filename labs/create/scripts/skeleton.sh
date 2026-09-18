#!/usr/bin/env bash
# Export a sandbox into labs/catalogue/ as a lab skeleton.
#
# This is the one bridge from a sandbox back to a lab, it runs in the instructor
# direction only, and it goes one way: after the export the lab is hand authored,
# and re-exporting over it would overwrite the handout.
#
# It is a host command and not a button in the editor, for two reasons that are
# both structural. The Tier A editor container's only writable mount is
# ~/.minilabs/sandboxes, so it cannot write to labs/catalogue/ at all. And a
# release tree has no labs/catalogue/ to write into: the release flattens the
# catalogue to labs/<lab>/ and the tree is a build output the next build
# overwrites. So this refuses to run anywhere but a source checkout, and the
# editor's part is to print the command.
#
# Usage:
#   labs/create/scripts/skeleton.sh <sandbox> [lab-name] [options]
#
#   <sandbox>    a name under ~/.minilabs/sandboxes, or a path to a project
#   [lab-name]   the catalogue directory to create; defaults to the sandbox name
#
#   --title <t>       the manifest title and the handout's title  (default: from the name)
#   --layer L2|L3|L4|L7   also the first middle segment of every container name
#   --dc <tag>        the second middle segment                   (default: LAB)
#   --category <c>    the menu category tui.tex names             (default: from the layer)
#   --no-figure       skip generating topology.tex
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

SANDBOX=""
LAB=""
PASS=()
DO_FIGURE=1

while [ $# -gt 0 ]; do
    case "$1" in
        --title|--layer|--dc|--category)
            PASS+=( "$1" "${2:?$1 needs a value}" ); shift 2 ;;
        --no-figure) DO_FIGURE=0; shift ;;
        -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
        -*) fail "unknown option: $1" ;;
        *)
            if   [ -z "$SANDBOX" ]; then SANDBOX="$1"
            elif [ -z "$LAB" ];     then LAB="$1"
            else fail "unexpected argument: $1"
            fi
            shift ;;
    esac
done

[ -n "$SANDBOX" ] || fail "which sandbox? $0 <sandbox> [lab-name]
Run List sandboxes in the TUI, or look in $SANDBOX_ROOT, for the names."

# ---------------------------------------------------------------------------
# 1. A source checkout, or nothing.
#
# labs/create/scripts/ sits two levels under the tree root in both a checkout
# and a release, so the root is the same walk either way and what distinguishes
# them is what is in it. All three markers are checked rather than one: a
# release tree could plausibly grow a labs/catalogue/ directory by hand, and
# writing a lab into it would produce a lab that the next release build deletes
# without ever having been in the source.
SRC="$( cd "$CREATE_DIR/../.." >/dev/null 2>&1 && pwd )"
for marker in labs/catalogue labs/release/make-release.sh labs/tools/topofig.py; do
    [ -e "$SRC/$marker" ] || fail "this is not a source checkout of MiniLabs: $SRC has no $marker.

Exporting a lab skeleton writes into labs/catalogue/, which only exists in the
source repository. A release tree is a build output: the next build overwrites
it, so a lab written here would disappear. Clone the source repository and run
this from there."
done

CATALOGUE="$SRC/labs/catalogue"

# ---------------------------------------------------------------------------
# 2. Resolve the sandbox and the lab name.
if [ -d "$SANDBOX" ] && [ -f "$SANDBOX/topology.toml" ]; then
    PROJECT_DIR="$( cd "$SANDBOX" >/dev/null 2>&1 && pwd )"
else
    case "$SANDBOX" in
        */*|..|.) fail "'$SANDBOX' is neither a sandbox name nor a directory holding a topology.toml" ;;
    esac
    PROJECT_DIR="$SANDBOX_ROOT/$SANDBOX"
    [ -f "$PROJECT_DIR/topology.toml" ] || fail "there is no sandbox called '$SANDBOX'.
Looked in $SANDBOX_ROOT. Run List sandboxes in the TUI to see what is there."
fi

[ -n "$LAB" ] || LAB="$( basename "$PROJECT_DIR" )"

# The catalogue directory name reaches container names, a menu row and a
# directory path, so it is held to what all three accept.
case "$LAB" in
    *[!a-z0-9-]*|-*|*-|"") fail "'$LAB' is not a catalogue directory name: use lower-case letters, digits and hyphens" ;;
esac

DEST="$CATALOGUE/$LAB"
[ -e "$DEST" ] && fail "labs/catalogue/$LAB already exists.

A skeleton is written once. After that the lab is hand authored, and exporting
over it would overwrite its handout and its answer key. Pick another name, or
remove that directory yourself if it is genuinely spare."

# ---------------------------------------------------------------------------
# 3. The binary.
# A checkout can hold four of them: the musl release the release build produces,
# an ordinary release build, a debug build, and whichever one was last copied to
# labs/create/bin. The newest wins rather than a fixed order, because the stale
# one exports a skeleton that does not match the code being worked on, and which
# of the four is stale changes with what was last built.
BIN=""
for candidate in \
    "$SRC/miniManager/target/x86_64-unknown-linux-musl/release/minicreate" \
    "$SRC/miniManager/target/release/minicreate" \
    "$SRC/miniManager/target/debug/minicreate" \
    "$MINICREATE"
do
    [ -x "$candidate" ] || continue
    if [ -z "$BIN" ] || [ "$candidate" -nt "$BIN" ]; then
        BIN="$candidate"
    fi
done
[ -n "$BIN" ] || fail "no minicreate binary found. Build one:
    ( cd $SRC/miniManager && cargo build --workspace )"

# ---------------------------------------------------------------------------
# 4. Write it.
log "sandbox:  $PROJECT_DIR"
log "lab:      labs/catalogue/$LAB"
log "using:    ${BIN#"$SRC"/}"
echo

"$BIN" skeleton "$PROJECT_DIR" --out "$DEST" --lab "$LAB" "${PASS[@]+"${PASS[@]}"}" || {
    # A failed export must not leave half a lab in the catalogue, where the next
    # release build would find a manifest.toml and try to ship it.
    [ -d "$DEST" ] && rm -rf "$DEST"
    fail "the export failed; nothing was left in the catalogue"
}

# ---------------------------------------------------------------------------
# 5. The topology figure.
# Generated from the lab's own scripts/topology.sh, which reads scripts/lib.sh,
# so the figure cannot drift from the addressing. It is regenerated by hand after
# any change to either.
if [ "$DO_FIGURE" -eq 1 ]; then
    if "$SRC/labs/tools/topofig.py" "$DEST" >/dev/null 2>&1; then
        log "figure:   topology.tex"
    else
        warn "topofig.py could not lay this topology out. handout.tex still
\\input{topology}s it, so generate it before rendering the handout:
    labs/tools/topofig.py labs/catalogue/$LAB"
    fi
fi

echo
cat <<NEXT
Written to labs/catalogue/$LAB.

It spawns as it stands, and it is not a lab yet. manifest.toml carries
status = "skeleton", and both release scripts refuse to build while that line is
there, which is what stops a topology with an empty handout reaching a student.

What is left, in the order it is usually done:

  1. Invoke Skill: lab-builder, which dispatches the four build roles, and read
     labs/catalogue/reflection-attacks as the worked example of the handout standard.
  2. Write handout.tex over the TODOs: the overview, the attack, the defence, and
     between 10 and 20 graded questions placed inline.
  3. Write solution/solutions.tex, one answer per question, same numbers.
  4. Write scripts/selftest.sh, which today exits non-zero and says so. It has to
     prove the attack works and that each defence stops it.
  5. Give each node its starting configuration under default_config/, the
     attacker pre-armed and the defender with the gap to close.
  6. Add the lab to labs/tui/config.toml under its category, with the six actions
     pointing at $DEST/scripts/.
  7. Delete the status line from manifest.toml. That is the deliberate act that
     lets the lab ship.
  8. Run scripts/selftest.sh, then take the lab through the verification pipeline
     (.claude/skills/lab-verification/SKILL.md).
NEXT
