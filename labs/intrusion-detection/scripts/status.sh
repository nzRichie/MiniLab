#!/usr/bin/env bash
# Print the lab's state and its own success oracle, so the learner reads what
# changed without shelling into five containers.
#
# It reads state and changes nothing. Nothing in this lab is hidden from the
# learner -- they play the attacker first and the defender second on one
# topology they can see all of -- so this action reports everything it can
# measure, including the addresses every probe is sent from.
#
# The oracle is three facts held at once, and each one on its own is easy:
# a server that replies to nobody stops the attacker, a server with no rules keeps
# the workstation working, and either of those keeps the web site up. Only the
# three together are the defence the lab asks for.
#
# Every probe it runs comes from lib.sh, so what this prints and what selftest.sh
# asserts cannot drift apart.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

hr()   { printf '%s\n' "------------------------------------------------------------"; }
sec()  { echo; hr; echo "$*"; hr; }
mark() { if [ "$1" = yes ]; then printf '  [done] '; else printf '  [    ] '; fi; }

if ! running "$SERVER_CTN"; then
    echo "The lab is not running ($SERVER_CTN is not up)."
    echo "Start it with the Spawn action, or scripts/spawn.sh."
    exit 1
fi

sec "Containers"
for ctn in "$SERVER_CTN" "$CLIENT_CTN" "$RTR_CTN" "$ATTACKER_CTN" "$CUSTOMER_CTN" \
           "$SW_IN_CTN" "$SW_OUT_CTN"; do
    if running "$ctn"; then printf '  %-28s up\n' "$ctn"
    else                    printf '  %-28s DOWN\n' "$ctn"; fi
done

# ---------------------------------------------------------------------------
sec "The server's filter table, INPUT chain"
rules="$( iptables_input )"
count="$( iptables_rule_count )"
if [ "${count:-0}" -eq 0 ]; then
    echo "  no rules. Every packet that reaches the server is passed to whatever"
    echo "  is listening, which is where Part 1 starts."
else
    echo "$rules" | sed 's/^/  /'
fi

# ---------------------------------------------------------------------------
sec "Suricata"
if ! suricata_running; then
    echo "  not running."
    if nfqueue_rule_present; then
        echo
        echo "  The INPUT chain still sends packets to a netfilter queue and nothing"
        echo "  is reading that queue, so the kernel is dropping every packet that"
        echo "  matches the rule. Start Suricata with -q ${NFQUEUE_NUM}, or delete the"
        echo "  NFQUEUE rule, or run Reset to baseline."
    fi
else
    mode="$( suricata_mode )"
    case "$mode" in
        ids) echo "  running in IDS mode: reading copies of packets off ${LAN_IF}." ;;
        ips) echo "  running in IPS mode: taking packets from netfilter queue ${NFQUEUE_NUM}" \
                  "and issuing a verdict on each one." ;;
        *)   echo "  running, but with neither -i nor -q on its command line." ;;
    esac
    if suricata_ready; then
        printf '  rules loaded: %s\n' "$( suricata_rules_loaded )"
    else
        echo "  still compiling its rules; it is not reading packets yet."
    fi
fi

if local_rules_configured; then
    echo "  suricata.yaml lists the local rules file."
else
    echo "  suricata.yaml does NOT list a local rules file, so nothing you write"
    echo "  in one would be loaded."
fi
if nfq_configured; then
    echo "  the nfq block is set to mode: accept."
fi

local_rules="$( docker exec "$SERVER_CTN" cat "$LOCAL_RULES" 2>/dev/null )"
if [ -n "$local_rules" ]; then
    echo
    echo "  $LOCAL_RULES:"
    echo "$local_rules" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
sec "What reaches the server"
echo "  Each line sends three TCP SYNs from the machine named and reports whether"
echo "  a SYN-ACK came back. REACHES means the service replied; BLOCKED means"
echo "  nothing came back before nping gave up."
echo

report_syn() {   # <label> <role> <port> [source address]
    if syn_reaches "$2" "$3" "${4:-}"; then printf '    %-46s REACHES\n' "$1"
    else                                    printf '    %-46s BLOCKED\n' "$1"; fi
}

report_syn "telnet (tcp/${TELNET_PORT}) from client ${CLIENT_IP}"        client   "$TELNET_PORT"
report_syn "telnet (tcp/${TELNET_PORT}) from attacker ${ATTACKER_IP}"    attacker "$TELNET_PORT" "$ATTACKER_IP"
report_syn "telnet (tcp/${TELNET_PORT}) from attacker ${ATTACKER_ALT_IP}" attacker "$TELNET_PORT" "$ATTACKER_ALT_IP"
report_syn "ssh (tcp/${SSH_PORT}) from client ${CLIENT_IP}"              client   "$SSH_PORT"

web_out="$( http_code customer )"
web_in="$( http_code client )"
echo
echo "  The web site is meant to be readable from anywhere. 200 is the site"
echo "  replying; 000 is curl giving up with no reply at all, which is what a"
echo "  dropped packet looks like to a client."
echo
printf '    http (tcp/%s) from customer %-24s %s\n' "$HTTP_PORT" "$CUSTOMER_IP" "$web_out"
printf '    http (tcp/%s) from client %-26s %s\n'   "$HTTP_PORT" "$CLIENT_IP"   "$web_in"

# ---------------------------------------------------------------------------
sec "What Suricata recorded"
if [ ! -n "$( docker exec "$SERVER_CTN" sh -c "test -s '$FAST_LOG' && echo x" 2>/dev/null )" ]; then
    echo "  the alert log is empty or does not exist yet."
else
    for sid in "$SID_INTERNAL" "$SID_EXTERNAL"; do
        n="$( alerts_for_sid "$sid" )"
        d="$( drops_for_sid "$sid" )"
        printf '    sid %s   %s alert(s), %s of them marked [Drop]\n' "$sid" "${n:-0}" "${d:-0}"
        last="$( last_alert_for_sid "$sid" )"
        [ -n "$last" ] && printf '      last: %s\n' "$last"
    done
    echo
    echo "  An alert line without [Drop] is a record that the packet matched and"
    echo "  went on its way. [Drop] means Suricata withheld it."
fi

# ---------------------------------------------------------------------------
sec "Where the lab stands"

out_blocked=no
if ! syn_reaches attacker "$TELNET_PORT" "$ATTACKER_IP" \
   && ! syn_reaches attacker "$TELNET_PORT" "$ATTACKER_ALT_IP"; then
    out_blocked=yes
fi
mark "$out_blocked"; echo "neither of the attacker's addresses reaches tcp/${TELNET_PORT}"

in_ok=no
syn_reaches client "$TELNET_PORT" && in_ok=yes
mark "$in_ok"; echo "the workstation on the inside still reaches tcp/${TELNET_PORT}"

web_ok=no
[ "$web_out" = 200 ] && web_ok=yes
mark "$web_ok"; echo "the web site still replies to ${CUSTOMER_IP} on the outside"

recorded=no
if [ "$( alerts_for_sid "$SID_EXTERNAL" )" -gt 0 ] 2>/dev/null; then recorded=yes; fi
mark "$recorded"; echo "Suricata has a record of what arrived from outside"

echo
echo "  The first three marks together are what the defence means here. Any one"
echo "  of them alone is easy to get: a server that replies to nobody has the first,"
echo "  and a server with no rules at all has the other two."
