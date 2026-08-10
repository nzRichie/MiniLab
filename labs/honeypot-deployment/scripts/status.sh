#!/usr/bin/env bash
# Show what the lab is doing, and the three-fact oracle the learner reads before
# and after each stage:
#
#   1. does a session from the attacker's network land on the decoy or on the
#      real production host?
#   2. has the decoy captured anything?
#   3. can the decoy reach the production host?
#
# and, paired with all three, the liveness check that stops a learner passing by
# breaking the thing they were meant to protect: can the management station still
# reach production?
#
# This prints state the learner could read for themselves on each device. It does
# not print any rule they are asked to write, and it never says how to write one.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

# Every probe below is deliberately non-authenticating and deliberately aimed
# away from the two things the learner is graded on counting. Status is an action
# the TUI invites a learner to run whenever they like, so a probe that logged in
# would add a session to the decoy's own capture log, and a probe that fetched
# the internal document would add a line to the log that says whether the pivot
# worked. Either one would move a number the learner is being asked to read.
#
# Reading the first line a server sends on connect. A real sshd sends its
# identification string immediately; that is all this needs to tell the real
# production host from anything standing in for it.
ssh_banner() {   # <from-ctn> <target> <port>
    docker exec "$1" sh -c "nc -w 4 $2 $3 </dev/null 2>/dev/null | head -1" \
        | tr -d '\r\n'
}

echo "== containers =="
docker ps --filter "name=${AS}_L7_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

echo "== router: four segments, and what it is enforcing =="
docker exec "$ROUTER_CTN" sysctl -n net.ipv4.ip_forward 2>/dev/null \
    | sed 's/^/  ip_forward = /'
docker exec "$ROUTER_CTN" ip -brief addr show 2>/dev/null \
    | grep -vE '^lo ' | sed 's/^/  /'
if redirect_active; then
    echo "  redirect    ACTIVE    ${PROD_IP}:${SSH_PORT} from ${EXT_SUBNET} is rewritten to the honeypot"
else
    echo "  redirect    absent    a session to ${PROD_IP}:${SSH_PORT} reaches the real host"
fi
if docker exec "$ROUTER_CTN" nft list ruleset 2>/dev/null \
        | grep -q "ip saddr ${HONEY_SUBNET} ct state new"; then
    echo "  containment ACTIVE    ${HONEY_SUBNET} may answer sessions but not start them"
else
    echo "  containment absent    the honeypot may open a connection to anywhere"
fi
echo

echo "== honeypot ($HONEY_CTN) =="
docker exec "$HONEY_CTN" ip -brief addr show 2>/dev/null \
    | grep -vE '^lo ' | sed 's/^/  /'
if cowrie_running; then
    echo "  cowrie      RUNNING   listening on ${HONEY_IP}:${HONEY_SSH_PORT}"
    echo "  captured    $( cowrie_login_count ) login(s), $( cowrie_command_count ) command(s)"
else
    echo "  cowrie      stopped   nothing is listening on ${HONEY_SSH_PORT}/tcp"
    if ! docker exec "$HONEY_CTN" test -f "$COWRIE_CFG" 2>/dev/null; then
        echo "              (${COWRIE_CFG} does not exist yet)"
    fi
fi
echo

echo "== production host ($PROD_CTN) =="
docker exec "$PROD_CTN" ip -brief addr show 2>/dev/null \
    | grep -vE '^lo ' | sed 's/^/  /'
printf '  sshd        %s\n' \
    "$( docker exec "$PROD_CTN" netstat -tln 2>/dev/null | grep -qE "[:.]${SSH_PORT} +.*LISTEN" \
        && echo "listening on ${SSH_PORT}/tcp" || echo "FAULT  nothing on ${SSH_PORT}/tcp" )"
printf '  lighttpd    %s\n' \
    "$( docker exec "$PROD_CTN" netstat -tln 2>/dev/null | grep -qE "[:.]${WEB_PORT} +.*LISTEN" \
        && echo "listening on ${WEB_PORT}/tcp" || echo "FAULT  nothing on ${WEB_PORT}/tcp" )"
echo "  logins       $( prod_login_count ) successful SSH login(s) recorded on the REAL host"
echo "  web fetches  $( prod_fetches_from_honeypot ) request(s) served to ${HONEY_IP}"
echo

echo "== oracle 1: where does a session from the attacker's network land? =="
# Read from the router's own rules and the decoy's own listener rather than by
# opening a session, for the reason given at the top of this file. The middle
# case is the one worth having: a redirect pointing at a decoy that is not
# running sends the attacker nowhere at all, which looks nothing like either the
# before state or the after state and is easy to arrive at by doing Part 2's two
# halves in the wrong order.
if ! redirect_active; then
    echo "  REAL HOST    nothing is rewritten, so ${PROD_IP}:${SSH_PORT} is the production host itself"
elif cowrie_running; then
    echo "  DECOY        ${PROD_IP}:${SSH_PORT} from ${EXT_SUBNET} is answered by ${HONEY_IP}:${HONEY_SSH_PORT}"
else
    echo "  NOWHERE      the redirect is active but nothing is listening on ${HONEY_IP}:${HONEY_SSH_PORT},"
    echo "               so a session from the attacker's network now reaches neither host"
fi
echo

echo "== oracle 2: can the honeypot reach the production host? =="
# Run from the honeypot container itself. It fetches "/" rather than the internal
# document, so running Status never moves the count of internal-document fetches
# printed above, which is the number Part 3 turns on.
if docker exec "$HONEY_CTN" curl -s -m 6 -o /dev/null \
        "http://${PROD_IP}/" 2>/dev/null; then
    echo "  REACHES      ${HONEY_IP} can open a connection to ${PROD_IP}:${WEB_PORT}"
else
    echo "  BLOCKED      ${HONEY_IP} cannot open a connection to ${PROD_IP}"
fi
echo

echo "== liveness: can the management station still reach production? =="
# The real sshd sends its identification string the moment a connection opens, so
# comparing what the management station is offered against what the production
# host itself offers settles which host answered, without authenticating.
admin_sees="$( ssh_banner "$ADMIN_CTN" "$PROD_IP" "$SSH_PORT" )"
prod_is="$( ssh_banner "$PROD_CTN" "127.0.0.1" "$SSH_PORT" )"
if [ -z "$admin_sees" ]; then
    echo "  BROKEN       ${ADMIN_IP} gets no answer at all from ${PROD_IP}:${SSH_PORT}."
elif [ "$admin_sees" = "$prod_is" ]; then
    echo "  OK           ${ADMIN_IP} still reaches the real production host (${admin_sees})"
else
    echo "  BROKEN       ${ADMIN_IP} is being answered by something other than the production"
    echo "               host: it offers '${admin_sees}', production offers '${prod_is}'."
fi
echo "  A defence that costs the administrators their access has not passed this lab,"
echo "  however well it stops the attacker."
