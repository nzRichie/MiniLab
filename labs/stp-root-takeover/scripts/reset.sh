#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline WITHOUT tearing it down: stop any
# running root claim, dismantle the attacker's bridge and put its second link back
# down, undo any learner defence on the switches, and re-apply the starter configs.
# A learner who broke the lab is back at the starting line.
#
# The one thing this cannot hurry is the spanning tree. Once the forged BPDUs stop,
# each switch still has to age the forged root out (max-age, 20s by default) and
# then walk the recovered ports through listening and learning (one forward delay,
# 15s, each). Reset waits for that rather than returning while the tree is still
# in motion, because a learner who reset and immediately pinged would otherwise
# see an outage that reset itself caused.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] stopping any active root claim and capture"
docker exec "$ATTACKER_CTN" pkill -f stp-root-claim 2>/dev/null || true
docker exec "$ATTACKER_CTN" pkill python3           2>/dev/null || true
for h in "${HOSTS[@]}"; do
    docker exec "$(ctn_of "$h")" pkill -f tcpdump 2>/dev/null || true
done

echo "[reset] dismantling the attacker's bridge and lowering its second link"
docker exec "$ATTACKER_CTN" sh -c "
    ip link set $ATTACKER_IF_A nomaster 2>/dev/null
    ip link set $ATTACKER_IF_B nomaster 2>/dev/null
    ip link del $ATTACKER_BRIDGE       2>/dev/null
    ip link set $ATTACKER_IF_B down    2>/dev/null
" >/dev/null 2>&1 || true

echo "[reset] removing any BPDU guard the learner applied to the access ports"
for pair in "${ACCESS_PORTS[@]}"; do
    set -- $pair
    docker exec "$1" ovs-vsctl remove port "$2" other_config stp-enable 2>/dev/null || true
done

echo "[reset] flushing neighbour caches on all hosts"
for h in "${HOSTS[@]}"; do
    docker exec "$(ctn_of "$h")" ip neigh flush all 2>/dev/null || true
done

echo "[reset] re-applying starter configs (restores the bridge priorities)"
for d in "${DEVICES[@]}"; do
    docker exec "$(ctn_of "$d")" "/home/${d}.sh" >/dev/null 2>&1 || true
done

# Wait for the tree to settle rather than reporting done while it is still moving.
# Poll for the state the baseline is defined by: all three switches naming a real
# bridge as root, and the victim reaching the gateway.
echo "[reset] waiting for the spanning tree to re-converge (up to 60s)"
for _ in $(seq 1 60); do
    settled=1
    for sw in "${SWITCHES[@]}"; do
        if stp_root_is_forged "$(ctn_of "$sw")"; then settled=0; break; fi
    done
    if [ "$settled" = 1 ] && docker exec "$VICTIM_CTN" ping -c1 -W1 "$GATEWAY_IP" >/dev/null 2>&1; then
        echo "[reset] baseline restored"
        exit 0
    fi
    sleep 1
done

echo "[reset] the tree had not settled after 60s; run status.sh to see where it is" >&2
exit 1
