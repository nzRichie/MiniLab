#!/usr/bin/env bash
# The lab's oracle. Prints, in one screen, every number the handout's questions
# read: both qdisc counters from the router, the admin's last four measurements,
# the victim's half-open count beside the backlog it is a fraction of, the
# router's filter with its packet counters, the uRPF drop counter, and the
# victim's rate-limit drop count.
#
# What it does NOT print is the arithmetic. The amplification factor of each
# reflector, the three-quarters relationship between syn-recv and the backlog,
# and the query rate one source needs to fill the link are what the learner is
# graded on working out from these numbers. Printing sent, dropped and
# overlimits is reporting; printing "85 % of the link" would be answering.
#
# Runs with hold = true in the TUI, so the learner reads it rather than watching
# it scroll past.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

running "$ROUTER_CTN" || {
    echo "The lab is not running ($ROUTER_CTN is not up). Spawn it first." >&2
    exit 1
}

rule() { printf '%s\n' "----------------------------------------------------------------------"; }

# --- the census and what is running ---------------------------------------
rule
up=0
for role in "${ALL_ROLES[@]}"; do running "$( ctn_of "$role" )" && up=$(( up + 1 )); done
echo "CONTAINERS: ${up}/14 up."
busy="$( flooding_sources )"
if [ -n "$busy" ]; then
    echo "  flood running on: $busy"
    echo "  (every run is bounded by its own --count and ends on its own)"
else
    echo "  no source is running a flood right now."
fi
rst=""
for h in "${SOURCES[@]}"; do source_drops_rst "$h" && rst="${rst:+$rst }$h"; done
if [ -n "$rst" ]; then
    echo "  dropping their own outbound RSTs toward the victim: $rst"
fi

# --- the bottleneck --------------------------------------------------------
rule
echo "THE BOTTLENECK, as the router's two shapers report it."
echo "  Read these as offered against delivered: 'Sent' is what got through,"
echo "  'dropped' is what did not, and the two together are what arrived."
echo
echo "  downlink, toward the victim (${IF_INSIDE}, ${DOWN_RATE}):"
qdisc_show "$IF_INSIDE" | sed 's/^/    /'
echo "    dropped $( qdisc_drop_pct "$IF_INSIDE" ) % of everything offered"
echo
echo "  uplink, away from the victim (${IF_FIELD}, ${UP_RATE}):"
qdisc_show "$IF_FIELD" | sed 's/^/    /'
echo "    dropped $( qdisc_drop_pct "$IF_FIELD" ) % of everything offered"

# --- the admin's measurements ---------------------------------------------
rule
echo "ADMIN WORKSTATION (${ADMIN_IP}), last reading of each measurement:"
state="$( probe_state )"
if [ -z "$state" ]; then
    echo "  nothing measured yet. On the admin, run:"
    echo "    probe --target ${SERVER_IP} --name ${VALID_NAME} all"
else
    ik="$( probe_field iperf 3 )"; il="$( probe_field iperf 4 )"
    wo="$( probe_field web 3 )";   wt="$( probe_field web 4 )"
    do_="$( probe_field dig 3 )";  dt="$( probe_field dig 4 )"
    pr="$( probe_field ping 3 )";  pl="$( probe_field ping 4 )"
    [ -n "$ik" ] && echo "  iperf3 UDP:  ${ik} kbit/s received, ${il} % lost"
    [ -n "$wo" ] && echo "  web fetch:   ${wo}/${wt} returned 200"
    [ -n "$do_" ] && echo "  dig ${VALID_NAME}: ${do_}/${dt} answered"
    [ -n "$pr" ] && echo "  ping:        ${pr} ms average, ${pl} % lost"
fi

# --- the victim's connection state ----------------------------------------
rule
sr="$( synrecv )"
mb="$( server_sysctl tcp_max_syn_backlog )"
sc="$( server_sysctl tcp_syncookies )"
cs="$( server_nstat TcpExtSyncookiesSent )"
echo "VICTIM (${SERVER_IP}), connection state:"
echo "  half-open connections (ss -Htan state syn-recv): ${sr:-0}"
echo "  net.ipv4.tcp_max_syn_backlog:                    ${mb:-?}"
echo "  net.ipv4.tcp_syncookies:                         ${sc:-?}"
echo "  TcpExtSyncookiesSent:                            ${cs:-0}"

# --- the victim's name server ---------------------------------------------
rule
echo "VICTIM's name server:"
if rrl_configured; then
    echo "  response rate limiting: CONFIGURED"
    docker exec "$SERVER_CTN" sh -c "grep -v '^//' '$RRL_CONF' | grep -v '^[[:space:]]*$'" 2>/dev/null | sed 's/^/    /'
else
    echo "  response rate limiting: none. Every response it can produce, it produces."
fi
echo "  responses dropped for rate limits (last rndc stats dump): $( rrl_drops )"

# --- the router's policy --------------------------------------------------
rule
n="$( router_rule_count )"
if [ "${n:-0}" -gt 0 ]; then
    echo "ROUTER: ${n} rule(s) in the FORWARD chain, with what each has absorbed:"
    router_rules | sed 's/^/    /'
else
    echo "ROUTER: no filtering. Every leg forwards to every other."
fi
echo
echo "  strict uRPF (rp_filter) per interface:  ${IF_INSIDE}=$( router_rp_filter "$IF_INSIDE" )  ${IF_FIELD}=$( router_rp_filter "$IF_FIELD" )  ${IF_OP}=$( router_rp_filter "$IF_OP" )"
echo "  TcpExtIPReversePathFilter (packets the check dropped): $( urpf_drops )"
echo "    that counter is cumulative for the life of the router container: a reset"
echo "    cannot zero a kernel counter, so read it twice and compare."
rule
