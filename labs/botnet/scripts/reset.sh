#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline, in place. No teardown.
#
# Five kinds of state accumulate while somebody works through this lab:
#
#   the running bots        one python3 per recruited field host, holding a
#                           pidfile under /run/minilabs
#   the controller          the process the learner started, plus its roster,
#                           results and standing task on disk
#   the router's policy      the iptables rules the learner wrote, whichever
#                           move they reached
#   the servers' state       the inside server's auth log, the loader's access
#                           log, and any password a task changed
#   the admin's probes       two loops that a re-applied config restarts
#
# The bots are killed first, by pidfile, with a fallback that matches the full
# payload path and never the interpreter name: `pkill python3` would take the
# lab's own instruments with it, which is the trap that made vps-hardening's
# reset silently lie. Then every device's starter config is re-applied, which
# is what restores the passwords, the sshd configs, the logs and the controller
# state to what Part 1 assumes -- re-running the config rather than undoing the
# learner's edits one at a time, because patching a file somebody has already
# edited is how a reset leaves a machine in a state neither the handout nor the
# answer key describes.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

running "$ROUTER_CTN" || {
    echo "The lab is not running ($ROUTER_CTN is not up). Spawn it first." >&2
    exit 1
}

# --- kill the population ---------------------------------------------------
# Every field host may hold a bot. Kill by pidfile first, then by the full
# argument path as a fallback for a bot started before its pidfile existed.
# The fallback matches on the payload path with pgrep and then kills each match
# except this very shell: `pkill -f '$BOT_PATH'` would match the reset command
# itself, because its own argument list contains that path, and kill the cleanup
# before it finished. Skipping $$ is what makes a full-argv match safe here.
for h in "${FIELD_HOSTS[@]}"; do
    ctn="$( ctn_of "$h" )"
    running "$ctn" || continue
    docker exec "$ctn" sh -c "
        if [ -f '$BOT_PIDFILE' ]; then kill \$(cat '$BOT_PIDFILE') 2>/dev/null || true; fi
        for p in \$(pgrep -f '$BOT_PATH' 2>/dev/null); do
            [ \"\$p\" = \"\$\$\" ] && continue
            kill \"\$p\" 2>/dev/null || true
        done
        rm -f '$BOT_PIDFILE' '$BOT_PATH' /tmp/bot.out
    " >/dev/null 2>&1 || true
done
log "stopped every bot on the field segment"

# --- re-apply every starter config ----------------------------------------
# The order is lib.sh's DEVICES order: router first so there is a path, then the
# servers, the field hosts, and the admin. c2.sh stops the controller and clears
# its roster; router.sh flushes FORWARD; loader.sh and server.sh empty their
# logs; the host and server configs restore the passwords a task may have
# changed; admin.sh restarts the two probes.
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    running "$ctn" || { log "$ctn is not running; skipping"; continue; }
    log "re-applying default_config/${d}.sh on $ctn"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec -i "$ctn" "/home/${d}.sh" >/dev/null
done

log "reset. The population is empty, the controller is stopped, the router has no"
log "policy, and both logs start from nothing. Start the controller on the c2 to"
log "begin again."
