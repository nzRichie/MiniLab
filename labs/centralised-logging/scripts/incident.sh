#!/usr/bin/env bash
# Run the incident, then delete the local log on the machine it happened to.
#
# This is the lab's seventh action, and the only one no other lab in the
# catalogue has. It exists because the incident has to happen AFTER the learner's
# forwarding and collector rules are in place: before that the collector holds
# nothing, and an incident nobody recorded is not something anybody can
# reconstruct. The learner cannot type these steps themselves either, for the
# obvious reason that then they would already know the answers.
#
# Nothing here is a simulation. Every line the learner reads afterwards is
# written by OpenSSH or by lighttpd about a session or a request that really
# happened:
#
#   1. routine   admin fetches two pages from the web service and logs in to db,
#                which is what an ordinary working day on this network looks like
#   2. break-in  web opens seven SSH sessions to db as dbadmin: six with a wrong
#                password and the seventh with the right one
#   3. pivot     from inside that seventh session, db opens an SSH session to
#                admin as ops, which is a direction nothing routine ever uses
#   4. cover     db's own /var/log/messages is deleted
#
# Step 4 is why the lab exists. Everything the sensitive host recorded about
# steps 2 and 3 is in that file and nowhere else on that machine, so what the
# learner can still answer afterwards is exactly what they arranged to copy
# elsewhere first.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

say() { echo "[incident] $*"; }

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=8 -o PreferredAuthentications=password
          -o PubkeyAuthentication=no)

# ---------------------------------------------------------------------------
# Refuse to run against a lab that is not collecting yet.
#
# The last step of this script destroys evidence. If the collector is not
# receiving db's messages at the moment that happens, the evidence is destroyed
# and no copy of it exists anywhere, and the only way back is `reset`. So the
# check is a probe, not an inspection of the configuration: it sends messages from
# db and looks for them at the collector, which is the same thing the learner is
# asked to prove for themselves at the end of Part 3. A configuration that looks
# right and does not work is exactly the case this has to catch.
if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CTN"; then
    echo "the lab is not running; spawn it first" >&2
    exit 1
fi

# probe_arrives retries rather than sending one message and hoping, and its window
# is deliberately longer than rsyslog's 30-second action resume interval: a
# forwarding action broken by a restart of the collector is suspended and
# discards what it is handed until that interval elapses, so a shorter check
# would refuse to run against a lab that is configured correctly.
say "checking the collector is receiving db's messages before anything is deleted"
say "(this can take up to a minute if the collector was restarted recently)"
if ! probe_arrives db perhost 6 >/dev/null; then
    echo >&2
    echo "The collector is not recording db's messages, so this would delete the only" >&2
    echo "copy of what is about to happen and leave nothing to reconstruct from." >&2
    echo >&2
    echo "Finish Parts 2 and 3 first: db has to forward to ${COLLECTOR_IP}, the collector" >&2
    echo "has to accept TCP on port ${SYSLOG_PORT}, and $( remote_file_of db ) has to be the" >&2
    echo "file db's messages land in. Run Status to see which of the three is missing." >&2
    exit 1
fi
say "the collector is recording db. Running the incident."

# ---------------------------------------------------------------------------
say "routine: admin requests two pages from the web service"
docker exec "$ADMIN_CTN" curl -s -o /dev/null --max-time 5 "http://${WEB_IP}/" || true
sleep 1
docker exec "$ADMIN_CTN" curl -s -o /dev/null --max-time 5 "http://${WEB_IP}${WEB_PROBE_PATH}" || true
sleep 1

say "routine: admin logs in to db as ${DB_USER}"
docker exec "$ADMIN_CTN" sshpass -p "$DB_PASS" \
    ssh "${SSH_OPTS[@]}" "${DB_USER}@${DB_IP}" 'id' >/dev/null 2>&1 || true
sleep 2

# ---------------------------------------------------------------------------
# The six wrong guesses. Each one is its own SSH connection with one
# authentication attempt in it, rather than six attempts inside one connection,
# because that is what a password-guessing tool does and because OpenSSH's
# MaxAuthTries would close the connection part way through the other shape.
say "break-in: ${FAILED_ATTEMPTS} wrong passwords from web against ${DB_USER}@db"
for pw in "${WRONG_PASSWORDS[@]}"; do
    docker exec "$WEB_CTN" sshpass -p "$pw" \
        ssh "${SSH_OPTS[@]}" "${DB_USER}@${DB_IP}" 'true' >/dev/null 2>&1 || true
    sleep 1
done

# ---------------------------------------------------------------------------
# The seventh attempt, and the pivot out of it. The second ssh really does run
# inside the first: its command line is executed by the shell OpenSSH started on
# db for this session, so the session on admin is opened by db, and the line
# admin records names db's address because that is where the packets came from.
say "break-in: the right password, and an onward session from db to ${ADMIN_USER}@admin"
inner="sshpass -p '${ADMIN_PASS}' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
inner="${inner} -o LogLevel=ERROR -o ConnectTimeout=8 -o PreferredAuthentications=password"
inner="${inner} -o PubkeyAuthentication=no ${ADMIN_USER}@${ADMIN_IP} id"
docker exec "$WEB_CTN" sshpass -p "$DB_PASS" \
    ssh "${SSH_OPTS[@]}" "${DB_USER}@${DB_IP}" "$inner" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Give the forwarding time to finish before the local copy goes. rsyslog hands a
# message to the forwarding action as soon as it has it, but "as soon as" is not
# "already", and deleting the file while the last few lines are still in the
# action queue would lose them from both copies at once.
say "waiting for the last of it to reach the collector"
for _ in $(seq 1 30); do
    if [ "$( remote_count db "$LATERAL_SIGNATURE" )" -ge 1 ] \
    || [ "$( remote_count admin "$LATERAL_SIGNATURE" )" -ge 1 ]; then break; fi
    sleep 0.5
done
sleep 2

# ---------------------------------------------------------------------------
# The cover-up. rsyslog holds this file open, so unlinking it does not stop the
# daemon writing: the next messages go to an inode with no name, which no `cat`
# can reach and no `ls` can show. That is the same property Part 3's rotation
# section is about, seen from the other side, and it is why `reset` restarts
# rsyslog rather than only recreating the file.
say "cover: deleting ${LOCAL_LOG} on db"
docker exec "$DB_CTN" rm -f "$LOCAL_LOG"

echo
say "done. db's own record of the last few minutes is gone."
say "What you can still answer is what you arranged to copy elsewhere first."
say "Read it with:  docker exec -it ${COLLECTOR_CTN} bash"
