#!/usr/bin/env bash
# Show what the lab is doing: containers, the bridge each switch believes is the
# root, every port's spanning-tree role and state, whether the two attacker access
# ports are protected, the victim's reach to the gateway, and the interception
# oracle: does victim-to-gateway traffic pass through the attacker?
#
# The root each switch names is the lab's central fact. A healthy network names
# S1. A network under attack names a bridge that is not any of the three, which is
# what the takeover looks like from the switch's own point of view.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${AS}_L2_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

echo "== who each switch thinks the root is =="
printf '  %-8s %-24s %s\n' "SWITCH" "ROOT BRIDGE ID" "VERDICT"
for sw in "${SWITCHES[@]}"; do
    ctn="$(ctn_of "$sw")"
    root="$( stp_root_of "$ctn" )"
    prio="${root%% *}"; mac="${root##* }"
    if [ -z "$prio" ]; then
        verdict="STP not running"
    elif [ "$prio" = "$FORGED_PRIO" ]; then
        verdict="FORGED  (no lab bridge uses priority ${FORGED_PRIO})"
    else
        verdict="legitimate"
    fi
    printf '  %-8s %-24s %s\n' "$sw" "${prio}/${mac}" "$verdict"
done
echo

echo "== port roles and states (a blocked port is how STP breaks the ring) =="
for sw in "${SWITCHES[@]}"; do
    ctn="$(ctn_of "$sw")"
    echo "  --- $sw ---"
    docker exec "$ctn" ovs-appctl stp/show 2>/dev/null \
        | awk '/^  '"${AS}"'-/ { printf "    %-14s %-11s %s\n", $1, $2, $3 }'
    # A port excluded from STP is not listed above at all, so say so explicitly:
    # that absence is exactly what the defence looks like once it is applied.
    for pair in "${ACCESS_PORTS[@]}"; do
        set -- $pair
        if [ "$1" = "$ctn" ]; then
            guard="$( docker exec "$ctn" ovs-vsctl get port "$2" other_config:stp-enable 2>/dev/null | tr -d '"' )"
            if [ "$guard" = "false" ]; then
                printf '    %-14s %s\n' "$2" "excluded from STP (BPDU guard applied)"
            fi
        fi
    done
done
echo

echo "== victim -> gateway (the honest traffic any defence must not break) =="
if docker exec "$VICTIM_CTN" ping -c2 -W1 "$GATEWAY_IP" >/dev/null 2>&1; then
    echo "  REACHABLE ($VICTIM_IP -> $GATEWAY_IP)"
else
    echo "  UNREACHABLE ($VICTIM_IP -> $GATEWAY_IP)   the tree is mid-convergence, or broken"
fi
echo

echo "== interception oracle: does victim traffic pass through the attacker? =="
# Capture on whichever interface the attacker is currently forwarding on: its
# bridge once Part 2 has built one, otherwise its single link into S2.
if docker exec "$ATTACKER_CTN" ip link show "$ATTACKER_BRIDGE" >/dev/null 2>&1; then
    watch_if="$ATTACKER_BRIDGE"
else
    watch_if="$ATTACKER_IF_A"
fi
# Warm the switches' MAC tables first. A topology change makes every switch age
# its table out fast, and a switch with no entry for a destination floods the
# frame everywhere, so for a second or two after any re-convergence the attacker
# sees traffic that is neither addressed to it nor routed through it. This oracle
# is asking whether the tree carries the victim through the attacker in steady
# state, so it warms up and then measures.
PROBES=10
ON_PATH_MIN=12
docker exec "$VICTIM_CTN" ping -c10 -i0.25 -W1 "$GATEWAY_IP" >/dev/null 2>&1 || true
sleep 1.5
docker exec "$ATTACKER_CTN" sh -c "rm -f /tmp/status.pcap" 2>/dev/null
docker exec -d "$ATTACKER_CTN" sh -c \
    "timeout 10 tcpdump -n -i $watch_if -w /tmp/status.pcap 'icmp and host $VICTIM_IP' >/dev/null 2>&1"
sleep 1
docker exec "$VICTIM_CTN" ping -c$PROBES -W1 "$GATEWAY_IP" >/dev/null 2>&1 || true
sleep 1.5
docker exec "$ATTACKER_CTN" pkill -f tcpdump >/dev/null 2>&1 || true
sleep 0.3
n="$( docker exec "$ATTACKER_CTN" sh -c 'tcpdump -nr /tmp/status.pcap 2>/dev/null | wc -l' | tr -d ' ' )"

# Judge against how much traffic there was to see, not against zero. An attacker
# the tree is routing through carries BOTH directions of every exchange, so what
# it sees scales with the probes sent: 20 frames for 10 echo requests. A bystander
# only catches the exchanges sent before the switches relearn the destination,
# which grows far more slowly: measured 0 to 8 frames off path against 16 to 20 on
# path, for the same ten probes. Reading any non-zero count
# as interception turns that residue into a false ON PATH, which is the worst way
# for this oracle to be wrong: it tells a learner the attack landed when it did
# not, and this check did exactly that at baseline before the threshold went in.
if [ "${n:-0}" -ge "$ON_PATH_MIN" ]; then
    echo "  ON PATH: the attacker carried ${n} of the victim's frames on $watch_if"
    echo "           (${PROBES} echo requests were sent, so both directions are crossing it)"
    echo "           victim-to-gateway traffic is being carried by the attacker"
elif [ "${n:-0}" -gt 0 ]; then
    echo "  OFF PATH: the attacker saw only ${n} frame(s) of ${PROBES} exchanges on $watch_if"
    echo "           that is flooding left over from a topology change, not interception:"
    echo "           a switch with no table entry for a destination sends the frame everywhere"
else
    echo "  OFF PATH: the attacker saw no victim traffic on $watch_if"
    echo "           the spanning tree is not routing the victim through it"
fi
