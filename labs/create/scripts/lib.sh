#!/usr/bin/env bash
# Shared definitions for the create-mode lifecycle scripts. Sourced by the
# others; no side effects.

CREATE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
MINILABS_HOME="${MINILABS_HOME:-$HOME/.minilabs}"
SANDBOX_ROOT="$MINILABS_HOME/sandboxes"
PRESET_DIR="$MINILABS_HOME/presets"
BLUEPRINT_DIR="$MINILABS_HOME/blueprints"
TOKEN_FILE="$MINILABS_HOME/editor-token"
STATE_FILE="$MINILABS_HOME/editor.json"

EDITOR_CTN="minilabs-editor"
EDITOR_IMAGE="minilabs-editor:1"
EDITOR_TAR="$CREATE_DIR/image/editor.tar"
MINICREATE="$CREATE_DIR/bin/minicreate"

# The port search starts here and walks upward.
PORT_BASE="${MINILABS_EDITOR_PORT:-8080}"
PORT_TRIES=20

# The sandbox scripts find the one copy of the privileged wiring helper through
# this. The release puts it at <root>/labs/lib/helper.sh, and a sandbox lives
# under $HOME, so nothing it can walk up to would find it.
export MINILABS_HELPER="${MINILABS_HELPER:-$( cd "$CREATE_DIR/.." >/dev/null 2>&1 && pwd )/lib/helper.sh}"

log()  { echo "[create] $*"; }
warn() { echo "[create] $*" >&2; }
fail() { echo "[create] $*" >&2; exit 1; }

# Docker has to be reachable. Checked with `docker info`, never by looking for
# ovs-vsctl on the host: Open vSwitch runs inside the switch containers, so a
# host check for it only breaks a docker-only machine.
need_docker() {
    docker info >/dev/null 2>&1 || fail "cannot reach the Docker daemon. Start it and check your access:
    rootless:  systemctl --user start docker
    rootful:   sudo systemctl start docker"
}

# Whether this daemon is rootless. It changes two things: the editor must not be
# given --user (container root already maps to the invoking uid), and the Docker
# socket lives under $XDG_RUNTIME_DIR rather than /var/run.
is_rootless() {
    docker info -f '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless
}

# Where this daemon's socket actually is. Resolved from the context rather than
# hardcoded, because a rootless daemon's is at $XDG_RUNTIME_DIR/docker.sock and a
# rootful one's is at /var/run/docker.sock, and guessing wrong fails in a way
# that reads as the editor being broken.
docker_socket() {
    local ep
    ep="$( docker context inspect -f '{{.Endpoints.docker.Host}}' 2>/dev/null || true )"
    case "$ep" in
        unix://*) echo "${ep#unix://}"; return 0 ;;
    esac
    ep="${DOCKER_HOST:-}"
    case "$ep" in
        unix://*) echo "${ep#unix://}"; return 0 ;;
    esac
    if is_rootless && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        echo "$XDG_RUNTIME_DIR/docker.sock"
    else
        echo /var/run/docker.sock
    fi
}

# Read one field out of the state file without needing a JSON tool.
state_field() {   # <field>
    [ -f "$STATE_FILE" ] || return 1
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" "$STATE_FILE" \
        | head -1
}

editor_running() {
    [ "$( docker inspect -f '{{.State.Running}}' "$EDITOR_CTN" 2>/dev/null )" = "true" ]
}

ensure_home() {
    mkdir -p "$MINILABS_HOME" "$SANDBOX_ROOT" "$PRESET_DIR" "$BLUEPRINT_DIR"
    # Never let these depend on the ambient umask: a rootful daemon's exec runs
    # with 0022 and a rootless one's with 0000, so a bare mkdir gives 755 on one
    # machine and 777 on the other.
    chmod 0700 "$MINILABS_HOME"
    chmod 0755 "$SANDBOX_ROOT" "$PRESET_DIR" "$BLUEPRINT_DIR"
}

# The project name inside a sandbox, which is what its containers are labelled
# with. It is not always the directory name: `minicreate emit --out` can put a
# project anywhere, and a user can rename a directory afterwards.
project_name_of() {   # <dir>
    sed -n 's/^name[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
        "$1/topology.toml" 2>/dev/null | head -1
}

# Every other sandbox whose project name is the same as this one's.
#
# This matters because teardown removes by label and the label carries the
# project name, not the directory: two sandboxes sharing a name means tearing
# down either one removes the other's containers as well.
same_name_as() {   # <dir>
    local want this d
    want="$( project_name_of "$1" )"
    [ -n "$want" ] || return 0
    for d in "$SANDBOX_ROOT"/*/; do
        [ -f "$d/topology.toml" ] || continue
        [ "$( cd "$d" && pwd )" = "$( cd "$1" && pwd )" ] && continue
        this="$( project_name_of "$d" )"
        [ "$this" = "$want" ] && basename "$d"
    done
}
