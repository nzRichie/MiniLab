#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline WITHOUT tearing it down: stop
# and un-configure the honeypot, drop both defences the learner added on the
# router, empty the logs the oracles read, and re-apply the starter configs. A
# learner who broke the lab, or who wants to run the whole sequence again from a
# clean set of counters, is back at the start.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping and un-configuring the honeypot"
# Cowrie holds a PID file under var/run and refuses to start twice, so it is
# stopped through its own launcher first and killed only if that fails. Removing
# the config and the logs is what makes the reset real: a learner re-running
# Part 2 must write cowrie.cfg again, and must not inherit a capture log that
# already contains the commands from their last attempt.
docker exec -u "$COWRIE_USER" -w "$COWRIE_HOME" "$HONEY_CTN" \
    sh -c "PATH=${COWRIE_BIN}:\$PATH cowrie stop" >/dev/null 2>&1 || true
docker exec "$HONEY_CTN" pkill -f 'twistd.*cowrie' 2>/dev/null || true
docker exec "$HONEY_CTN" sh -c \
    "rm -f '$COWRIE_CFG' '$COWRIE_USERDB' '${COWRIE_HOME}'/var/run/* ; \
     rm -f '${COWRIE_HOME}'/var/log/cowrie/* ; \
     rm -f '${COWRIE_HOME}'/var/lib/cowrie/downloads/* '${COWRIE_HOME}'/var/lib/cowrie/tty/*" \
    2>/dev/null || true

echo "[reset] removing the redirect and the containment rule from the router"
# The redirect lives in its own table, so it goes as a unit. The containment rule
# was appended to the edge filter's chain, which the router's starter config
# rebuilds from scratch below, so deleting that table here is what removes it.
docker exec "$ROUTER_CTN" nft delete table ip deception 2>/dev/null || true
docker exec "$ROUTER_CTN" nft delete table inet edge    2>/dev/null || true

echo "[reset] stopping any capture left running"
for d in "${DEVICES[@]}"; do
    docker exec "$( ctn_of "$d" )" pkill -f tcpdump 2>/dev/null || true
done

echo "[reset] re-applying starter configs"
# Every starter config is written to survive a second run, so this rebuilds the
# router's edge filter, restarts production's two daemons, and truncates both
# logs the oracles count lines in.
for d in "${DEVICES[@]}"; do
    docker exec "$( ctn_of "$d" )" "/home/${d}.sh" >/dev/null 2>&1 || true
done

echo "[reset] baseline restored: no decoy, no redirect, no containment"
