#!/bin/sh
# The admin workstation's SSH probe.
#
# The site's admin logs into the inside server over SSH on a slow period, to do
# whatever a human does on a server. It is the reason tcp/22 toward the server
# cannot simply be switched off: a defence that blocks port 22 outright stops
# the botnet's guessing and this login at once, and this login is the one the
# graded end state has to keep working.
#
# It authenticates as a maintenance account with a password on no wordlist, so
# the botnet guessing a different account's password never affects it, and a
# defender changing what the botnet is guessing never breaks it. It writes one
# line per run to its state file: the epoch second, ok or fail, and the marker
# the server prints on a successful login.
set -u

: "${SERVER_ADDR:?}"
: "${SSH_USER:?}"
: "${SSH_PASS:?}"
: "${SSH_INTERVAL:?}"
: "${SSH_STATE:?}"

mkdir -p "$( dirname "$SSH_STATE" )"

while :; do
    now="$( date +%s )"
    out="$( sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=6 -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no -o LogLevel=ERROR \
        "${SSH_USER}@${SERVER_ADDR}" 'echo MINILABS-ADMIN-OK' 2>/dev/null )"
    case "$out" in
        *MINILABS-ADMIN-OK*) echo "$now ok login"       > "$SSH_STATE" ;;
        *)                   echo "$now fail no-login"   > "$SSH_STATE" ;;
    esac
    sleep "$SSH_INTERVAL"
done
