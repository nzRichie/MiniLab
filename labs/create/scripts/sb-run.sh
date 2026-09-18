#!/usr/bin/env bash
# Run one lifecycle action against one sandbox.
#
# A row per sandbox is not possible, and three separate things keep it that way:
# the engine loads ./config.toml once at startup and never reloads, labs are not
# auto-discovered, and the release build fails for any `script =` path that is
# not in the shipped tree, which a path under ~/.minilabs can never be. Even a
# hand-written absolute path would fail, because there is no shell to expand `~`.
#
# So the sandbox is an argument, and this resolves it.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ACTION="${1:-}"
PROJECT="${2:-}"
shift 2 2>/dev/null || true

[ -n "$ACTION" ]  || fail "sb-run.sh needs an action"
[ -n "$PROJECT" ] || fail "which sandbox? Run List sandboxes to see the names."

case "$ACTION" in
    spawn|status|shell|reset|teardown) ;;
    *) fail "'$ACTION' is not a sandbox action" ;;
esac

# One path segment, nothing else. Checked before any filesystem call, so a name
# like ../../.ssh is refused rather than resolved and then found to be outside.
case "$PROJECT" in
    */*|..|.|"")     fail "'$PROJECT' is not a sandbox name: it must be one name, with no /" ;;
    .*)              fail "'$PROJECT' is not a sandbox name: it must not start with a dot" ;;
esac

DIR="$SANDBOX_ROOT/$PROJECT"
[ -d "$DIR" ] || fail "there is no sandbox called '$PROJECT'.
Run List sandboxes to see what is there."
[ -f "$DIR/topology.toml" ] || fail "'$PROJECT' is not a sandbox: it holds no topology.toml"

# Two sandboxes with the same project name are a trap, not an inconvenience.
# Every container a sandbox creates is labelled with the project name, and
# teardown removes what carries the label, so tearing down either one would take
# the other's containers with it. Refused rather than warned about: by the time
# the warning is read the containers are already gone.
clashes="$( same_name_as "$DIR" )"
if [ -n "$clashes" ]; then
    fail "'$PROJECT' and $( echo "$clashes" | tr '\n' ' ' )share the project name
'$( project_name_of "$DIR" )'.
Every container a sandbox creates is labelled with that name, and teardown
removes what carries the label, so tearing down one would remove the other's
containers too. Rename one: change the 'name' at the top of its topology.toml
and emit it again."
fi

# An imported sandbox holds code that will run as root inside a container: an
# init script per node, run_args and cap_add, and a preset Dockerfile whose RUN
# lines execute at build time. Import marks it, and spawn is where the mark is
# enforced, because spawn is the step that runs any of it. Every other action is
# allowed: looking at a sandbox, and tearing one down, must never be blocked.
if [ "$ACTION" = "spawn" ] && [ -f "$DIR/.unreviewed" ]; then
    fail "'$PROJECT' was imported and nobody has reviewed what it runs.
A shared sandbox carries init scripts, docker run arguments, added capabilities
and preset Dockerfiles, and all of them execute. Look at them first:
    $MINICREATE review $DIR
and re-run that with --confirm once the list is what you expect. The editor's
import dialog shows the same list."
fi

SCRIPT="$DIR/scripts/$ACTION.sh"
if [ ! -f "$SCRIPT" ]; then
    fail "'$PROJECT' has no $ACTION.sh yet.
It has been drawn but not emitted. Emit it in the editor, or run:
    $MINICREATE emit $DIR --out $DIR"
fi

exec bash "$SCRIPT" "$@"
