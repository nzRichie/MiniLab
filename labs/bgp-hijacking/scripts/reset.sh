#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline WITHOUT tearing it down: withdraw
# the attacker's announcements, put the victim back to announcing only its
# aggregate, undo the RPKI configuration and the ROA the learner created, re-apply
# every router's starter config, and restart the identity banners.
#
# A learner who broke the lab is back at a converged network where AS1 originates
# 1.0.0.0/22, nobody validates, and the only ROA in the RIR is the one AS6 shipped
# with. The RIR and validator keep running: their certificates and trust anchor are
# expensive to rebuild and none of it is state the learner can damage.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] withdrawing any hijack on AS${ATTACKER_AS}"
"$LAB_DIR/scripts/hijack.sh" clear >/dev/null 2>&1 || true

echo "[reset] returning AS${VICTIM_AS} to announcing only ${VICTIM_PREFIX}"
"$LAB_DIR/scripts/deaggregate.sh" aggregate >/dev/null 2>&1 || true

# Every removal is its own guarded vtysh call: `no ...` on something that was never
# configured errors, and vtysh abandons the rest of a multi-command invocation
# after an error. Inlined rather than calling solution/, which the student release
# strips.
echo "[reset] removing RPKI validation and the ROV import policy from the routers"
# Attaching ROV inbound REPLACED the baseline ALLOW map on the AS6 session, so the
# undo is to put ALLOW back, not to delete ROV and leave the session with no
# inbound policy: FRR 9.1 enforces `bgp ebgp-requires-policy` and a neighbour with
# no inbound map exchanges nothing at all.
R_ENFORCE="$( router_ctn "$ROV_ENFORCE_AS" )"
docker exec "$R_ENFORCE" vtysh -c "conf t" -c "router bgp ${ROV_ENFORCE_AS}" \
    -c "address-family ipv4 unicast" \
    -c "neighbor ${ATTACKER_LINK_IP} route-map ALLOW in" >/dev/null 2>&1 || true
docker exec "$R_ENFORCE" vtysh -c "conf t" -c "no route-map ROV" >/dev/null 2>&1 || true

# Removing the cache is what actually turns validation off: with no cache the
# router reports "No connection to RPKI cache server" and every route falls back to
# NotFound. FRR 9.1 keeps the empty `rpki` stanza in the running config afterwards
# and `no rpki` does not delete it, so the config is left one line untidier than it
# started. That line has no effect and re-running the Part 2 steps overwrites it.
for link in "${RPKI_LINKS[@]}"; do
    read -r as vip _ _ <<<"$link"
    rc="$( router_ctn "$as" )"
    docker exec "$rc" vtysh -c "conf t" -c "rpki" \
        -c "no rpki cache ${vip} ${RTR_PORT} preference 1" -c "exit" >/dev/null 2>&1 || true
done

# Drop the victim's ROA, whichever of the two forms the learner ended up with, so
# Part 2 can be worked through again from a clean start.
if docker ps --format '{{.Names}}' | grep -q "^${RIR_CTN}$"; then
    echo "[reset] removing the ${VICTIM_PREFIX} ROA from the RIR"
    krillc roas update --ca "AS${VICTIM_AS}" --remove "$VICTIM_ROA_CORRECT"   >/dev/null 2>&1 || true
    krillc roas update --ca "AS${VICTIM_AS}" --remove "$VICTIM_ROA_NOMAXLEN"  >/dev/null 2>&1 || true
fi

echo "[reset] re-applying starter configs on every router"
for as in "${ASES[@]}"; do
    docker exec "$( router_ctn "$as" )" "/home/r${as}.sh" >/dev/null 2>&1 || true
done

# The routers cached the old validation states; without a soft clear they keep
# them even though the cache is gone. Same refresh the handout teaches in Part 2.
for as in "${RPKI_CACHE_ASES[@]}"; do
    docker exec "$( router_ctn "$as" )" vtysh \
        -c "clear bgp ipv4 unicast * soft in" >/dev/null 2>&1 || true
done

echo "[reset] restarting identity banners"
for pair in "${VICTIM_AS}:${VICTIM_BANNER}" "${ATTACKER_AS}:${ATTACKER_BANNER}"; do
    as="${pair%%:*}"; msg="${pair#*:}"
    docker exec "$( host_ctn "$as" )" pkill -f banner-server 2>/dev/null || true
    docker exec "$( host_ctn "$as" )" pkill python3 2>/dev/null || true
    docker exec -d "$( host_ctn "$as" )" banner-server "$msg"
done

echo "[reset] baseline restored"
