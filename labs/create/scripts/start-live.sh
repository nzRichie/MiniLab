#!/usr/bin/env bash
# Start the editor WITH access to the Docker daemon (Tier B).
#
# Written now, and deliberately refuses to start anything until Tier B is built.
# The explanation below is the point of the script and prints whichever answer
# was given, because the menu prompt cannot carry it: the engine gives a prompt
# 22 characters of inner width at 80 columns and does not mark a clipped one as
# clipped, so a sentence naming root equivalence loses the word "root" on any
# terminal narrower than about 190 columns.
#
# The script cannot ask the question itself either. The engine pipes stdout and
# stderr and leaves stdin inherited, and the TUI holds the terminal in raw mode
# reading its own keys, so a `read` here would fight the menu for keystrokes.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ANSWER="${1:-no}"

cat <<'EXPLAIN'
What "with Docker access" means

  This mounts the Docker socket into the editor container. Anything that can
  reach that socket can start a container that mounts the whole filesystem, so
  it can read and write every file your account can, and on a rootful daemon
  every file on the machine, including other people's.

  In other words: giving the editor Docker access gives it the same power your
  shell has over this machine, and on a rootful daemon that is root.

What it buys

  The editor can see which of your sandboxes are running, warn you before you
  spawn something whose name is already taken, and start and stop a sandbox from
  the canvas instead of from the menu.

  Everything else works without it. Drawing, validating, addressing and emitting
  are all done without touching Docker at all, which is why the plain Start
  editor action exists and is the one to use unless you specifically want the
  live view.

If you are on a shared or university machine

  Use the plain editor. The live one is worth it on a laptop you own.

EXPLAIN

if [ "$ANSWER" != "yes" ]; then
    echo "Nothing was started. Use the plain Start editor action, or pick yes here"
    echo "if you want the live view and have read the above."
    exit 0
fi

# Tier B is M6. Saying so plainly beats starting something half-built that then
# behaves in ways nobody can explain.
echo "The live editor is not built yet."
echo
echo "You answered yes, so here is what will happen when it is: the socket at"
echo "  $( docker_socket )"
echo "will be mounted into the editor container, with the warning above still true."
echo
echo "Until then, use the plain Start editor action."
exit 0
