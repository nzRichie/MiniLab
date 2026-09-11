#!/usr/bin/env bash
# Print the lab's state and its own success oracle, so the learner reads what
# each defence stage changed without shelling into five containers.
#
# The oracle is two facts held at once. Containment means the callback is dead
# AND the page still answers a legitimate request. Either one alone is easy: a
# gateway that forwards nothing kills the callback and also breaks the page's
# reachability check, and a gateway that forwards everything keeps the page
# working and hands the attacker a shell.
#
# It reads state and it does not grade anything the learner is marked on. Three
# of its probes do send a request through the injection: that is the only way to
# report what an injected command can currently do, which is the question the
# whole of Part 2 answers. The webshell probe removes the file it wrote either
# way, and the callback probe's marker read leaves nothing behind, so running
# Status repeatedly does not change the lab.
#
# Every probe comes from lib.sh, so what this prints and what selftest.sh asserts
# cannot drift apart.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

hr()  { printf '%s\n' "------------------------------------------------------------"; }
sec() { echo; hr; echo "$*"; hr; }
mark() { if [ "$1" = yes ]; then printf '  [done] '; else printf '  [    ] '; fi; }

if ! running "$GW_CTN"; then
    echo "The lab is not running ($GW_CTN is not up)."
    echo "Start it with the Spawn action, or scripts/spawn.sh."
    exit 1
fi

sec "Containers"
for ctn in "$GW_CTN" "$WEB_CTN" "$OPS_CTN" "$MON_CTN" "$ATTACKER_CTN" \
           "$SW_IN_CTN" "$SW_OUT_CTN"; do
    if running "$ctn"; then printf '  %-28s up\n' "$ctn"
    else                    printf '  %-28s DOWN\n' "$ctn"; fi
done

if ! lighttpd_running; then
    echo
    echo "  lighttpd is not running on $WEB_CTN, so the page answers nothing."
    echo "  Run the Reset action to put the appliance back to its starter state."
fi

# ---------------------------------------------------------------------------
sec "The appliance's configuration"
printf '  %-48s %s\n' "the web server runs its CGI as the account" "$( lighttpd_account )"
printf '  %-48s %s\n' "${CGI_DIR} is owned by" "$( webroot_owner )"
printf '  %-48s %s\n' "anyone outside that owner may write there" "$( webroot_group_other_writable )"

# ---------------------------------------------------------------------------
sec "The gateway's egress policy"
rules="$( nft_ruleset )"
if [ -z "$rules" ]; then
    echo "  none. The gateway forwards every packet between the two segments,"
    echo "  in both directions, whoever originated it."
else
    echo "$rules" | sed 's/^/  /'
fi

# ---------------------------------------------------------------------------
sec "What an injected command can do right now"
echo "  Three probes, sent now from ${ATTACKER_IP} through the page's host parameter:"
echo

uid="$( injected_uid )"
printf '    %-52s %s\n' "it runs as uid" "${uid:-no answer}"
printf '    %-52s %s\n' "it can read ${MARKER_FILE}" "$( marker_readable )"
printf '    %-52s %s\n' "it can leave a second CGI in the webroot and run it" "$( persistence_possible )"

# ---------------------------------------------------------------------------
sec "Does the callback still get out?"
echo "  One probe: arm a listener on ${ATTACKER_IP}:${LISTEN_PORT}, then inject a"
echo "  command that reads the appliance's key and pipes it to that listener."
echo
read -r connected got_marker <<< "$( callback_probe )"
printf '    %-52s %s\n' "a connection reached the listener" "$connected"
printf '    %-52s %s\n' "the listener received the key" "$got_marker"

# ---------------------------------------------------------------------------
sec "Does the page still answer a legitimate request?"
serves="$( endpoint_serves )"
if [ "$serves" = ok ]; then
    printf '    a reachability check for %s from ops returns echo replies   OK\n' "$MON_IP"
else
    printf '    a reachability check for %s from ops returns no echo reply  FAIL\n' "$MON_IP"
fi

# ---------------------------------------------------------------------------
sec "Where the lab stands"

shut=no
[ "$connected" = no ] && shut=yes
mark "$shut"; echo "the callback is dead: nothing the appliance opens reaches the listener"

works=no
[ "$serves" = ok ] && works=yes
mark "$works"; echo "the page still works: a reachability check for ${MON_IP} returns echo replies"

held=no
[ "$shut" = yes ] && [ "$works" = yes ] && held=yes
mark "$held"; echo "the appliance is contained: both facts hold at once"

echo
echo "  Two of the three stages do not appear on that list, and that is the"
echo "  lesson rather than an omission. Handing the server a service account and"
echo "  taking the webroot back change what the injected command is worth: read"
echo "  the uid, the key and the webshell lines above to see them. Neither one"
echo "  stops the callback, because opening an outbound connection needs neither"
echo "  root nor a writable disk. Only the gateway's allowlist stops that."
