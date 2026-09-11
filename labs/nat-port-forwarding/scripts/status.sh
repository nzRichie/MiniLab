#!/usr/bin/env bash
# Show what the lab is doing, and its success oracle.
#
# The oracle is three fetches, and each one is answered by a different pair of
# rules. A private client reaching the far side needs source NAT. The far side
# reaching the published service needs destination NAT. A private client reaching
# that same published address needs both, plus a second source NAT for the
# turn-around. Each fetch is scored on two things and not one: whether it
# returned the marker of the service it was aimed at, and which source address
# that service saw. The second is what separates a working translation from a
# path that happened to work for another reason.
#
# The sections above the oracle exist because a red stage says nothing about
# which of six rules is wrong: addressing, the outside host's deliberately empty
# routing table, the ruleset itself and the connection-tracking table each fail
# in a different place and each fail with the oracle looking identical.
#
# Nothing here configures anything. It reads state, makes the same requests a
# learner makes, and prints what came back.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

pass=0; fail=0
mark() {   # <yes|no> <text>
    if [ "$1" = "yes" ]; then pass=$((pass+1)); printf '  [ ok ] %s\n' "$2"
    else                      fail=$((fail+1)); printf '  [    ] %s\n' "$2"; fi
}

echo "== containers =="
docker ps --filter "name=${AS}_L3_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -v netadmin_helper
echo

# ---------------------------------------------------------------------------
echo "== addressing =="
printf '  %-12s %-30s %s\n' DEVICE ADDRESS "DEFAULT ROUTE"
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    addrs="$( docker exec "$ctn" sh -c \
        "ip -o -4 addr show 2>/dev/null | awk '\$2 != \"lo\" {print \$4}' | paste -sd, -" 2>/dev/null )"
    gw="$( docker exec "$ctn" sh -c \
        "ip -o -4 route show default 2>/dev/null | awk '{print \$3}' | head -1" 2>/dev/null )"
    printf '  %-12s %-30s %s\n' "$d" "${addrs:-none}" "${gw:-none}"
done
echo
echo "  The outside host has no default route and no route into the private prefix."
echo "  That is deliberate, it is what every host beyond a NAT looks like, and it is"
echo "  why a reply addressed to ${INSIDE1_IP} has nowhere to go:"
printf '    %s\n' "$( route_get outside "$INSIDE1_IP" )"
echo

# ---------------------------------------------------------------------------
echo "== the router's translation rules =="
rules="$( nat_ruleset )"
if [ -n "$rules" ]; then
    printf '%s\n' "$rules" | sed 's/^/  /'
else
    echo "  none: the router has no nat table loaded, so it forwards without translating."
fi
echo

# ---------------------------------------------------------------------------
# Stage 1. Outbound: the direction traditional NAT exists to serve.
echo "== stage 1: a private client reaching the far side =="
body="$( http_body inside-1 "$OUTBOUND_URL" )"
case "$body" in
    *"$OUTSIDE_MARKER"*)
        mark yes "inside-1 fetched the outside site"
        src="$( seen_source inside-1 "$OUTBOUND_WHOAMI" )"
        if [ "$src" = "$ROUTER_OUT_IP" ]; then
            mark yes "the outside server saw the request come from ${ROUTER_OUT_IP}, the router's outside address"
        else
            mark no  "the outside server saw '${src:-nothing}', expected ${ROUTER_OUT_IP}"
        fi ;;
    *)
        mark no "inside-1 could not fetch the outside site (${OUTBOUND_URL})"
        printf '         %s\n' "$( http_message inside-1 "$OUTBOUND_URL" )"
        echo   "         The request reaches the far side either way; what is missing is a"
        echo   "         source address the far side can answer." ;;
esac
echo

# ---------------------------------------------------------------------------
# Stage 2. Inbound: the exception traditional NAT serves with a static map.
echo "== stage 2: the far side reaching the published service =="
body="$( http_body outside "$PUBLISHED_URL" )"
case "$body" in
    *"$INSIDE_MARKER"*)
        mark yes "outside fetched the private web service through ${ROUTER_OUT_IP}:${PUBLIC_PORT}"
        src="$( seen_source outside "$PUBLISHED_WHOAMI" )"
        if [ "$src" = "$OUTSIDE_IP" ]; then
            mark yes "the private server saw the request come from ${OUTSIDE_IP}, the real client"
        else
            mark no  "the private server saw '${src:-nothing}', expected ${OUTSIDE_IP}"
        fi ;;
    *)
        mark no "outside could not reach the published service (${PUBLISHED_URL})"
        printf '         %s\n' "$( http_message outside "$PUBLISHED_URL" )" ;;
esac
echo

# ---------------------------------------------------------------------------
# Stage 3. The same published address, asked for from inside the site.
echo "== stage 3: a private client reaching the published service =="
body="$( http_body inside-1 "$PUBLISHED_URL" )"
case "$body" in
    *"$INSIDE_MARKER"*)
        mark yes "inside-1 fetched the private web service through ${ROUTER_OUT_IP}:${PUBLIC_PORT}"
        src="$( seen_source inside-1 "$PUBLISHED_WHOAMI" )"
        if [ "$src" = "$ROUTER_IN_IP" ]; then
            mark yes "the private server saw the request come from ${ROUTER_IN_IP}, the router's inside address"
        else
            mark no  "the private server saw '${src:-nothing}', expected ${ROUTER_IN_IP}"
        fi ;;
    *)
        mark no "inside-1 could not reach the published service (${PUBLISHED_URL})"
        printf '         %s\n' "$( http_message inside-1 "$PUBLISHED_URL" )"
        echo   "         A refusal and a timeout mean different things here: a refusal is the"
        echo   "         router answering for itself, a timeout is a reply that arrived from an"
        echo   "         address the client never sent to." ;;
esac
echo

# ---------------------------------------------------------------------------
echo "== the router's connection-tracking table =="
echo "  One row per flow. The first tuple is what the client sent, the second is"
echo "  what the router expects the reply to look like; every field that differs"
echo "  between them is a field being translated."
rows="$( conntrack_rows -p tcp )"
if [ -n "$rows" ]; then
    printf '%s\n' "$rows" | sed 's/^/  /'
else
    echo "  empty."
fi
echo
echo "  Last line of each web service's access log:"
printf '    outside:   %s\n' "$( last_log_line outside )"
printf '    webserver: %s\n' "$( last_log_line webserver )"
echo

# ---------------------------------------------------------------------------
echo "== summary =="
printf '  %d check(s) passing, %d not.\n' "$pass" "$fail"
if [ "$fail" -eq 0 ]; then
    echo "  All three directions work and each one is seen at the far end with the"
    echo "  address it should be. The lab is finished."
else
    echo "  Stage 1 needs a source NAT rule, stage 2 a destination NAT rule, and"
    echo "  stage 3 needs the destination rule to match traffic arriving from the"
    echo "  private side as well, plus a source NAT for the turn-around."
fi
exit 0
