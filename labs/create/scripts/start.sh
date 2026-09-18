#!/usr/bin/env bash
# Start the create-mode editor (Tier A: no Docker socket).
#
# Starts detached and exits. It must not block: the engine's Done on a held view
# drops the view without killing the child, so a server run in the foreground is
# orphaned with no way back to it.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

need_docker
ensure_home

if editor_running; then
    log "the editor is already running"
    exec "$( dirname "${BASH_SOURCE[0]}" )/status.sh"
fi
docker rm -f "$EDITOR_CTN" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# The image is loaded from the tarball the release ships, never pulled. A
# university lab machine may have no registry access, which is the whole reason
# the release carries a `docker save` of it.
if ! docker image inspect "$EDITOR_IMAGE" >/dev/null 2>&1; then
    [ -f "$EDITOR_TAR" ] || fail "the editor image is not on this machine and
$EDITOR_TAR is missing, so there is nothing to load it from.
The release was built with --no-editor-image. Rebuild it without that flag."
    log "loading the editor image from $( basename "$EDITOR_TAR" ) (first run only)"
    docker load -i "$EDITOR_TAR" >/dev/null || fail "could not load $EDITOR_TAR"
fi

# ---------------------------------------------------------------------------
# The token. 32 random bytes, hex-encoded, in a file only this user can read.
#
# It is bind-mounted read-only and never passed through -e or the container's
# argv: `docker inspect` shows both to anyone who can reach the daemon, which on
# a rootful daemon is everyone in the docker group.
umask 077
head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"
TOKEN="$( cat "$TOKEN_FILE" )"

# Which uid the editor runs as, and why the two daemons need opposite answers.
#
# The container has to be able to read a 0600 token owned by this user, and to
# write into the sandboxes mount as this user.
#
#   rootful:  host uid N is container uid N, so --user "$(id -u):$(id -g)".
#             Without it the container's root would own every file it writes
#             into the bind mount.
#
#   rootless: container root maps to THIS user, and every other container uid
#             maps to a subuid that owns nothing of ours. The image's own
#             non-root user is therefore one of those subuids, and it cannot read
#             a 0600 file this user owns: the editor exits with
#             "cannot read the token ... Permission denied". So --user 0:0, which
#             on a rootless daemon is not root on the host at all.
if is_rootless; then
    USER_ARG=( --user 0:0 )
else
    USER_ARG=( --user "$(id -u):$(id -g)" )
fi

# ---------------------------------------------------------------------------
# Pick a port by trying to start on it.
#
# Always the long 127.0.0.1:<port>:8080 form. The short <port>:8080 form binds
# 0.0.0.0 and puts the editor on the building's network, which on a shared
# university machine means every other user on it.
#
# The collision that matters is another user's container already holding the
# port, under a different HOME, so no lock of ours is contended and the bind
# failure is the signal. The flock still serialises two starts by this user.
# Braces, not a bare `exec ... 2>/dev/null`. `exec 9>f 2>/dev/null` sets fd 9 and
# then redirects stderr to /dev/null for the REST OF THE SHELL, so every later
# failure exits silently: the script returns 1 and says nothing at all.
{ exec 9>"$STATE_FILE.lock"; } 2>/dev/null || true
flock 9 2>/dev/null || true

started=0
for i in $( seq 0 $(( PORT_TRIES - 1 )) ); do
    PORT=$(( PORT_BASE + i ))
    if docker run -d --name "$EDITOR_CTN" \
        --label minilabs.create=editor \
        "${USER_ARG[@]}" \
        -p "127.0.0.1:${PORT}:8080" \
        -v "$SANDBOX_ROOT:/sandboxes" \
        -v "$PRESET_DIR:/presets:ro" \
        -v "$BLUEPRINT_DIR:/blueprints" \
        -v "$TOKEN_FILE:/run/secrets/editor-token:ro" \
        "$EDITOR_IMAGE" >/dev/null 2>"$MINILABS_HOME/.start.err"; then
        started=1
        break
    fi
    docker rm -f "$EDITOR_CTN" >/dev/null 2>&1 || true
    if [ "$i" -gt 0 ]; then
        log "port $PORT is taken, trying $(( PORT + 1 ))"
    fi
done

if [ "$started" -ne 1 ]; then
    warn "could not start the editor on any port from $PORT_BASE to $(( PORT_BASE + PORT_TRIES - 1 ))"
    sed 's/^/    /' "$MINILABS_HOME/.start.err" >&2 2>/dev/null || true
    exit 1
fi

URL="http://127.0.0.1:${PORT}/${TOKEN}/"
cat > "$STATE_FILE" <<JSON
{
  "container": "$EDITOR_CTN",
  "port": $PORT,
  "url": "$URL",
  "tier": "A"
}
JSON
chmod 0600 "$STATE_FILE"

# Wait for it to answer, so the URL printed is one that works.
#
# `docker run -d` returning 0 only means the container was created. A server that
# exits immediately, which is what a token it cannot read looks like, leaves a
# published port bound and nothing behind it: the URL is printed, the page never
# loads, and nothing says why. So the readiness wait is fatal, and it prints the
# container's own last words.
ready=0
for _ in $( seq 1 60 ); do
    if [ "$( docker inspect -f '{{.State.Running}}' "$EDITOR_CTN" 2>/dev/null )" != "true" ]; then
        break
    fi
    code="$( curl -s -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || true )"
    if [ "$code" = "200" ]; then
        ready=1
        break
    fi
    sleep 0.25
done

if [ "$ready" -ne 1 ]; then
    warn "the editor container started but is not serving. It said:"
    docker logs "$EDITOR_CTN" 2>&1 | sed 's/^/    /' | head -20 >&2
    docker rm -f "$EDITOR_CTN" >/dev/null 2>&1 || true
    rm -f "$STATE_FILE"
    exit 1
fi

log "the editor is running, with no access to Docker."
echo
echo "  Open this:"
echo "    $URL"
echo
echo "  On another machine, forward the port first:"
echo "    ssh -L ${PORT}:127.0.0.1:${PORT} $( id -un )@$( hostname )"
echo "  then open the same URL there. The link already carries the token."
echo
echo "  It listens on 127.0.0.1 only. Anyone who can read the URL can edit"
echo "  your sandboxes, so treat it like a password."
