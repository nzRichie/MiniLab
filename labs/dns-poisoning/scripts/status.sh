#!/usr/bin/env bash
# Show what the lab is doing, and its success oracle.
#
# The oracle has two halves, and the lab is only readable with both. The control
# plane half is the address the resolver hands back for www.uni.lab and the rcode
# it hands it back with: that is what the resolver decided. The data plane half is
# which machine answers an HTTP request for that address: that is what actually
# happened. A poisoned resolver shows the attacker's address and the impostor's
# banner; a validating resolver refuses to answer at all, which looks like a
# failure and is the defence working.
#
# It also prints the three resolver settings the lab turns on and off, because a
# learner in the middle of Part 2 needs to see which ones are in force.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${AS}_L7_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

echo "== addressing =="
printf '  %-28s %s\n' "campus (via $SW)"  "$CAMPUS_SUBNET"
printf '  %-28s %s\n' "  resolver"        "$RESOLVER_IP"
printf '  %-28s %s\n' "  victim"          "$VICTIM_IP"
printf '  %-28s %s\n' "authoritative link" "$AUTH_SUBNET"
printf '  %-28s %s\n' "  auth ($TARGET_ZONE)" "$AUTH_IP"
printf '  %-28s %s\n' "attacker link"     "$HOSTILE_SUBNET"
printf '  %-28s %s\n' "  attacker"        "$ATTACKER_IP"
echo

echo "== resolver: the three settings this lab turns on and off =="
if docker exec "$RESOLVER_CTN" test -f "$HARDENING_CONF" 2>/dev/null; then
    docker exec "$RESOLVER_CTN" grep -vE '^\s*(//|$)' "$HARDENING_CONF" 2>/dev/null \
        | sed 's/^/  /'
else
    echo "  (no $HARDENING_CONF on the resolver)"
fi
if docker exec "$RESOLVER_CTN" grep -q 'trust-anchors' "$TRUST_ANCHOR_INSTALLED" 2>/dev/null; then
    echo "  trust anchor for ${TARGET_ZONE}: installed"
else
    echo "  trust anchor for ${TARGET_ZONE}: not installed"
fi
if named_running "$RESOLVER_CTN"; then
    echo "  named: running"
else
    echo "  named: NOT RUNNING; the resolver answers nothing until it is started again"
fi
echo

echo "== authoritative server =="
if named_running "$AUTH_CTN"; then
    echo "  named: running, ${TARGET_ZONE} served on ${AUTH_IP}:53"
else
    echo "  named: NOT RUNNING"
fi
if docker exec "$AUTH_CTN" pgrep -f slow-link >/dev/null 2>&1; then
    echo "  slow-link: running, every reply held back by ${AUTH_DELAY_MS} ms"
else
    echo "  slow-link: NOT RUNNING; the race window is gone and the attack cannot land"
fi
qtime="$( docker exec "$VICTIM_CTN" dig +timeout=3 +tries=1 "@${AUTH_IP}" \
              "$TARGET_NAME" A 2>/dev/null | sed -n 's/^;; Query time: //p' | head -1 )"
echo "  measured round trip from the campus, asking the server directly: ${qtime:-no answer}"
echo

echo "== oracle: what does ${TARGET_NAME} resolve to, and who answers there? =="
addr="$( resolved_address )"
rcode="$( resolved_status )"
banner="$( served_banner )"

printf '  %-22s %s\n' "resolver returns" "${addr:-nothing}"
printf '  %-22s %s\n' "with rcode" "${rcode:-no reply}"

if [ "$addr" = "$AUTH_IP" ]; then
    echo "  CLEAN      the resolver holds the real address for ${TARGET_NAME}"
elif [ "$addr" = "$ATTACKER_IP" ]; then
    echo "  POISONED   the resolver holds the attacker's address for ${TARGET_NAME}"
elif [ "$rcode" = "SERVFAIL" ]; then
    echo "  REFUSED    the resolver will not hand over an answer it could not verify"
elif [ "$rcode" = "REFUSED" ]; then
    echo "  REFUSED    the resolver will not answer this client at all"
else
    echo "  UNKNOWN    the resolver returned neither address; the lab may be mid-restart"
fi

if [ -n "$banner" ]; then
    printf '  %-22s %s\n' "and http says" "$banner"
else
    printf '  %-22s %s\n' "and http says" "nothing answered on port ${WEB_PORT}"
fi
echo

echo "== oracle: can the attacker still make the resolver look a name up? =="
if docker exec "$ATTACKER_CTN" dig +short +timeout=3 +tries=1 \
        "@${RESOLVER_IP}" "probe.${PROBE_ZONE}" A 2>/dev/null | grep -q '^[0-9]'; then
    echo "  OPEN       the resolver recurses for the attacker's network, so the"
    echo "             attacker can start a query whenever it likes and race the answer"
else
    echo "  RESTRICTED the resolver will not recurse for the attacker's network, so the"
    echo "             attacker has to wait for a campus host to ask on its own"
fi
