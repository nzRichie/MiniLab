#!/usr/bin/env bash
# The victim's control-plane answer to the hijack, run against the AS1 router over
# vtysh. This is the scripted equivalent of the commands the handout has the learner
# type by hand in Part 2; it takes NO defaults, so a stage names exactly the set of
# prefixes AS1 announces after it runs.
#
# Usage: deaggregate.sh <aggregate|split23|split24>
#   aggregate  announce 1.0.0.0/22 only                     -- the baseline
#   split23    announce 1.0.0.0/22 + the two /23s           -- answering a /23 hijack
#   split24    announce 1.0.0.0/22 + the four /24s          -- the floor
#
# The aggregate is kept at every stage, which is what an operator actually does:
# the more-specifics win where they are heard, and the aggregate still covers any
# network that filters long prefixes. /24 is the end of the ladder -- the global
# routing table does not accept anything longer, so there is no split25.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

R1="$( router_ctn "$VICTIM_AS" )"
STAGE="${1:-}"

vt() { docker exec "$R1" vtysh "$@"; }

# Everything below the aggregate that any stage can announce, so a stage change
# clears whatever the previous one left.
ALL_MORE_SPECIFICS=( "${VICTIM_DEAGG_23[@]}" "${VICTIM_DEAGG_24[@]}" )

# One guarded vtysh call per removal: `no network` on a prefix that is not
# announced errors, and vtysh abandons every remaining -c after an error.
withdraw_more_specifics() {
    local p
    for p in "${ALL_MORE_SPECIFICS[@]}"; do
        vt -c "conf t" -c "router bgp ${VICTIM_AS}" -c "address-family ipv4 unicast" \
           -c "no network ${p}" >/dev/null 2>&1 || true
    done
    for p in "${ALL_MORE_SPECIFICS[@]}"; do
        vt -c "conf t" -c "no ip route ${p} Null0" >/dev/null 2>&1 || true
    done
}

# The discard route makes `network` originate the prefix whether or not a matching
# route already exists. For 1.0.0.0/24 the connected host link already provides
# one and the static is inert; for the rest of the allocation, which carries no
# hosts, the static is what makes the announcement possible at all.
announce() {
    local p="$1"
    vt -c "conf t" -c "ip route ${p} Null0"
    vt -c "conf t" -c "router bgp ${VICTIM_AS}" -c "address-family ipv4 unicast" \
       -c "network ${p}"
}

case "$STAGE" in
  aggregate)
    withdraw_more_specifics
    echo "[deaggregate] AS${VICTIM_AS} announces only ${VICTIM_PREFIX}."
    ;;
  split23)
    withdraw_more_specifics
    for p in "${VICTIM_DEAGG_23[@]}"; do announce "$p"; done
    echo "[deaggregate] AS${VICTIM_AS} announces ${VICTIM_PREFIX} + ${VICTIM_DEAGG_23[*]}."
    echo "[deaggregate] The /23s now match the attacker's /23 in length, so the contest returns to AS-path."
    ;;
  split24)
    withdraw_more_specifics
    for p in "${VICTIM_DEAGG_24[@]}"; do announce "$p"; done
    echo "[deaggregate] AS${VICTIM_AS} announces ${VICTIM_PREFIX} + ${VICTIM_DEAGG_24[*]}."
    echo "[deaggregate] This is the floor: /24 is the longest prefix the routing table accepts."
    ;;
  *)
    echo "usage: deaggregate.sh <aggregate|split23|split24>" >&2
    exit 1
    ;;
esac
