#!/usr/bin/env bash
# Show what the lab is doing, and the self-contained oracle: is every service
# answering on its own host, and can the attacker reach the target network at all.
#
# It deliberately does NOT list the addresses inside the target /24, how many
# hosts are in there, which port each one answers on, or what software is behind
# that port. Those are exactly what Parts 1 and 2 have the learner find out, and
# this is a menu action the TUI invites them to run, so printing them here would
# hand over the graded work. Each host is checked from INSIDE its own container
# instead, and a healthy one reports OK with no detail, which proves the lab
# works without surveying it on the learner's behalf. The full map is in the
# instructor answer key.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${AS}_L4_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

echo "== router: forwarding between the attacker and the target network =="
docker exec "$ROUTER_CTN" sysctl -n net.ipv4.ip_forward 2>/dev/null \
    | sed 's/^/  ip_forward = /'
docker exec "$ROUTER_CTN" ip -brief addr show 2>/dev/null \
    | grep -vE '^lo ' | sed 's/^/  /'
echo

echo "== attacker ($ATTACKER_CTN) =="
docker exec "$ATTACKER_CTN" ip -brief addr show 2>/dev/null \
    | grep -vE '^lo ' | sed 's/^/  /'
docker exec "$ATTACKER_CTN" ip route show default 2>/dev/null | sed 's/^/  default via /;s/default via default via /default via /'
echo

# Can the attacker get to the target network at all? The router's inside address
# is the one address in that subnet the handout already gives the learner, so
# probing it reveals nothing the learner does not have.
echo "== oracle: can the attacker reach the target network? =="
if docker exec "$ATTACKER_CTN" ping -c 2 -W 2 "$ROUTER_TGT_IP" >/dev/null 2>&1; then
    echo "  REACHABLE  ${TGT_SUBNET} is routed: ${ROUTER_TGT_IP} answers from the attacker"
else
    echo "  UNREACHABLE  ${ROUTER_TGT_IP} does not answer; the survey cannot run"
fi
echo

# Per-service health, checked inside each container. `listens <ctn> <port>` asks
# the host itself what it has bound, rather than scanning it from outside.
listens() { docker exec "$1" netstat -tln 2>/dev/null | grep -qE "[:.]$2 +.*LISTEN"; }
report()  { printf '  %-9s %s\n' "$1" "$2"; }

# A healthy host reports OK and NOTHING ELSE. Naming the daemon and the port on
# the way past ("lighttpd is listening on 80/tcp") answered most of Part 2 in a
# menu action the TUI invites the learner to run before they scan anything, and
# contradicted this script's own promise above. On a FAULT the detail is printed,
# because at that point the lab is broken and the learner needs to know how.
echo "== oracle: is every host in the target network in the state the lab expects? =="

if listens "$WEB_CTN" "$WEB_PORT"; then
    report host1 "OK"
else
    report host1 "FAULT  nothing is listening on ${WEB_PORT}/tcp"
fi

# The host that runs nothing is healthy precisely when it has nothing bound.
if docker exec "$IDLE_CTN" netstat -tln 2>/dev/null | grep -qE 'LISTEN'; then
    report host2 "FAULT  something is listening here; this host is meant to have nothing"
else
    report host2 "OK"
fi

if listens "$FTP_CTN" "$FTP_PORT"; then
    if docker exec "$FTP_CTN" test -f "${FTP_ROOT}/pub/${FTP_LEAK_FILE}"; then
        report host3 "OK"
    else
        report host3 "FAULT  vsftpd is listening on ${FTP_PORT}/tcp, but its share is empty"
    fi
else
    report host3 "FAULT  nothing is listening on ${FTP_PORT}/tcp"
fi

if listens "$TELNET_CTN" "$TELNET_PORT"; then
    if docker exec "$TELNET_CTN" id "$TELNET_USER" >/dev/null 2>&1; then
        report host4 "OK"
    else
        report host4 "FAULT  telnetd is listening on ${TELNET_PORT}/tcp, but the account is missing"
    fi
else
    report host4 "FAULT  nothing is listening on ${TELNET_PORT}/tcp"
fi

echo
echo "  Which addresses these hosts hold, which of them a ping sweep finds, and"
echo "  what each one runs are what Parts 1 and 2 have you work out. None of it is"
echo "  printed here."
