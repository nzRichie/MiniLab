#!/usr/bin/env bash
# Print the lab's state and its own success oracle, so the learner reads what
# changed without shelling into four containers.
#
# It reads state and changes nothing. In particular it never breaks a backend:
# the failure count across a kill is the lab's headline number and measuring it
# means causing the failure, which is the learner's job and selftest.sh's, not an
# oracle's. What this reports is the standing state and the last twenty requests.
#
# Every probe it runs comes from lib.sh, so what this prints and what selftest.sh
# asserts cannot drift apart.
#
#   1  the pool exists and both backends are serving a share of the traffic
#   2  each server is checked, and a server whose check fails leaves the pool
#      while its site keeps serving
#   3  a retry policy is configured, so a connection that fails is re-sent to a
#      different server rather than turning into a response the client can see
#   4  the connect timeout fits inside the client's own patience
#   5  a server can be taken out on purpose, with nothing broken
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

hr()  { printf '%s\n' "------------------------------------------------------------"; }
sec() { echo; hr; echo "$*"; hr; }
mark() { if [ "$1" = yes ]; then printf '  [done] '; else printf '  [    ] '; fi; }

if ! running "$PROXY_CTN"; then
    echo "The lab is not running ($PROXY_CTN is not up)."
    echo "Start it with the Spawn action, or scripts/spawn.sh."
    exit 1
fi

sec "Containers"
for ctn in "$CLIENT_CTN" "$PROXY_CTN" "$WEB1_CTN" "$WEB2_CTN" "$SW_CTN"; do
    if running "$ctn"; then printf '  %-28s up\n' "$ctn"
    else                    printf '  %-28s DOWN\n' "$ctn"; fi
done

# ---------------------------------------------------------------------------
sec "The proxy"
if hap_config_valid; then
    echo "  $HAPROXY_CFG parses: yes"
else
    echo "  $HAPROXY_CFG parses: NO. haproxy -c says:"
    hap_config_message | sed 's/^/    /'
fi

if hap_running; then
    echo "  haproxy is running"
else
    echo "  haproxy is NOT running."
    echo "  Nothing is listening on ${PROXY_FRONT_IP}:${VIP_PORT}, so the client gets no answer at all."
fi

echo
echo "  What the configuration currently says. A blank value is a directive that"
echo "  is not in the file, which is not the same as one set to a default:"
printf '    %-22s %s\n' "balance"           "$( cfg_directive '^[[:space:]]*balance ' )"
printf '    %-22s %s\n' "health check"      "$( cfg_directive '^[[:space:]]*option httpchk' )"
printf '    %-22s %s\n' "check request"     "$( cfg_directive '^[[:space:]]*http-check send' )"
printf '    %-22s %s\n' "check expects"     "$( cfg_directive '^[[:space:]]*http-check expect' )"
printf '    %-22s %s\n' "retries"           "$( cfg_directive '^[[:space:]]*retries ' )"
printf '    %-22s %s\n' "redispatch"        "$( cfg_directive '^[[:space:]]*option redispatch' )"
printf '    %-22s %s\n' "timeout connect"   "$( cfg_directive '^[[:space:]]*timeout connect' )"

# ---------------------------------------------------------------------------
sec "The pool, as HAProxy sees it"
if ! hap_running; then
    echo "  haproxy is not running, so there is no pool to report."
else
    echo "  status:  UP / DOWN, or DRAIN and MAINT when a server was taken out on"
    echo "           purpose. 'no check' means the server line carries no check"
    echo "           keyword, so HAProxy has never probed it and assumes it works."
    echo "  check:   the result of the last completed health check."
    echo "           L7OK   the check got the status code it expects"
    echo "           L7STS  the service replied with a DIFFERENT status code"
    echo "           L4CON  the connection was refused: nothing is listening"
    echo "           L4TOUT the connection got no answer at all"
    echo "  sessions: requests this server has handled since haproxy started."
    echo
    printf '    %-8s %-10s %-8s %-9s %s\n' server address status check sessions
    for w in "${BACKENDS[@]}"; do
        printf '    %-8s %-10s %-8s %-9s %s\n' \
            "$w" "$( backend_ip "$w" )" "$( server_status "$w" )" \
            "$( server_check "$w" )" "$( server_stot "$w" )"
    done
fi

# ---------------------------------------------------------------------------
sec "What the client sees: 20 requests to $VIP_URL"
tmp="$( mktemp )"
trap 'rm -f "$tmp"' EXIT
client_loop 20 0.05 > "$tmp"
echo "  status codes:  $( loop_codes "$tmp" )"
echo "  served by:     $( loop_split "$tmp" )"
echo "  slowest:       $( loop_maxtime "$tmp" )s"
echo "  not 2xx:       $( loop_nonok "$tmp" ) of $( loop_total "$tmp" )"
echo
echo "  A dash under 'served by' is a request no backend answered: either the"
echo "  proxy replied with an error of its own, or nothing replied at all."

# ---------------------------------------------------------------------------
sec "Reaching the backends"
echo "  The proxy does not forward, so the client has no path to the back segment."
echo "  Every backend connection in this lab is one HAProxy opened itself."
echo
printf '    client -> %-22s tcp/%s  %s\n' "$WEB1_IP (web1)"  "$WEB_PORT" "$( port_state "$CLIENT_CTN" "$WEB1_IP" "$WEB_PORT" )"
printf '    client -> %-22s tcp/%s  %s\n' "$PROXY_FRONT_IP (proxy)" "$VIP_PORT" "$( port_state "$CLIENT_CTN" "$PROXY_FRONT_IP" "$VIP_PORT" )"
echo
echo "  From the proxy, which does have a route to them. This is how a backend"
echo "  that HAProxy has taken out of the pool can be shown still serving:"
for w in "${BACKENDS[@]}"; do
    printf '    proxy  -> %-22s site says %-6s /health returns %s\n' \
        "$( backend_ip "$w" ) ($w)" "'$( backend_body "$w" )'" "$( backend_health_code "$w" )"
done

# ---------------------------------------------------------------------------
sec "Where the lab stands"

pool_up=no
if hap_running && [ "$( loop_served "$tmp" web1 )" -gt 0 ] && [ "$( loop_served "$tmp" web2 )" -gt 0 ]; then
    pool_up=yes
fi
mark "$pool_up"; echo "Part 1  the pool balances over both backends"

checked=no
if [ -n "$( cfg_directive '^[[:space:]]*option httpchk' )" ] \
   && [ "$( server_status web1 )" != "no check" ] && [ "$( server_status web2 )" != "no check" ]; then
    checked=yes
fi
mark "$checked"; echo "Part 2  each server carries an active health check"

retry=no
retries_line="$( cfg_directive '^[[:space:]]*retries ' )"
retries_n="${retries_line##* }"
case "$retries_n" in
    ''|*[!0-9]*) retries_n=0 ;;
esac
if [ "$retries_n" -ge 1 ] && [ -n "$( cfg_directive '^[[:space:]]*option redispatch' )" ]; then
    retry=yes
fi
mark "$retry"; echo "Part 3  a failed connection is retried on a DIFFERENT server"

# The connect timeout has to leave room for every attempt the retry policy will
# make inside the time the client is prepared to wait. Reported in milliseconds
# because that is the only unit the comparison can be made in without parsing
# three spellings of the same duration.
ct_line="$( cfg_directive '^[[:space:]]*timeout connect' )"
ct_ms="$( printf '%s' "$ct_line" | awk '{ v = $NF
    if (v ~ /ms$/)      { sub(/ms$/, "", v); print v + 0 }
    else if (v ~ /s$/)  { sub(/s$/, "", v);  print v * 1000 }
    else if (v ~ /^[0-9]+$/) { print v + 0 }
    else print 0 }' )"
budget_ms=$(( CURL_MAX_TIME * 1000 ))
fits=no
if [ "${ct_ms:-0}" -gt 0 ] && [ $(( ct_ms * (retries_n + 1) )) -lt "$budget_ms" ]; then
    fits=yes
fi
mark "$fits"
printf 'Part 4  %s attempt(s) of %sms fit inside the client'"'"'s %ss patience\n' \
    "$(( retries_n + 1 ))" "${ct_ms:-0}" "$CURL_MAX_TIME"

taken_out=no
for w in "${BACKENDS[@]}"; do
    case "$( server_status "$w" )" in DRAIN|MAINT) taken_out=yes ;; esac
done
mark "$taken_out"; echo "Part 5  a server is currently held out of the pool on purpose (drain or maint)"

echo
echo "  The failure count across a backend dying is the number this lab is graded"
echo "  on, and it cannot be read here: measuring it means causing the failure."
echo "  Run the request loop on the client and break a backend while it runs."
