#!/usr/bin/env bash
# Show what the range is doing, and hand back exactly what the learner's tier
# entitles them to and nothing more.
#
# It deliberately does NOT print which addresses hold a host, how many there are,
# which ports answer, or what software is behind them. Those are the whole of the
# exercise, and this is a menu action the TUI invites the learner to run. What it
# does print is the seed (so a range can be reproduced or reported), the
# attacker's own address and gateway (which the learner can read off their own
# interface anyway), whatever the tier hands over, and a health check that says
# whether the range is intact without describing it.
#
# The health check runs from INSIDE each container, so a host reports OK without
# anything being scanned on the learner's behalf.
set -uo pipefail
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$HERE/lib.sh"

if ! range_is_up; then
    echo "No range is spawned."
    echo "Use Spawn, pick a tier, and leave the seed blank for a fresh range."
    exit 0
fi

env_txt="$( docker exec "$ATTACKER_CTN" cat /etc/minilabs/range.env 2>/dev/null )"
eval "${env_txt:-}"

echo "== this range =="
echo "  SEED ${RANGE_SEED:-?}   TIER ${RANGE_TIER:-?}"
echo "  Spawn with the same tier and seed to get this exact range back."
echo
# The mutator is printed and the shape is not. One of them says how the range
# behaves and the other says how many segments are out there, and only the first
# is something a learner is not scored on finding.
if [ -n "${RANGE_MUTATOR:-}" ] && [ "${RANGE_MUTATOR}" != vanilla ]; then
    echo "== how this one behaves =="
    case "$RANGE_MUTATOR" in
        quiet)       echo "  quiet: most machines here do not answer an echo request." ;;
        noisy)       echo "  noisy: some machines here hold open ports with nothing behind them." ;;
        relocated)   echo "  relocated: services are not on the ports their registry entries name." ;;
        chatty)      echo "  chatty: SNMP is answering on most machines." ;;
        locked-down) echo "  locked down: shut ports are dropped rather than refused nearly everywhere." ;;
        legacy)      echo "  legacy: a cleartext estate. No SSH anywhere on it." ;;
        segmented)   echo "  segmented: more empty subnets than usual, and not all of them answer alike." ;;
    esac
    echo "  It changes how the range behaves, not what is on it. What is on it is"
    echo "  still yours to find."
    echo
fi

echo "== what you have been given =="
att_ip="$( docker exec "$ATTACKER_CTN" ip -brief -4 addr show 2>/dev/null \
           | awk '$1 != "lo" && $2 == "UP" && $3 != "" {print $3; exit}' )"
att_gw="$( docker exec "$ATTACKER_CTN" ip route show default 2>/dev/null | awk '{print $3; exit}' )"
echo "  your address   ${att_ip:-unknown}"
echo "  your gateway   ${att_gw:-unknown}"
# The opening is drawn per range, so what this line means changes between spawns
# and the line has to say which kind it is. A list of candidate blocks and a list
# of confirmed segments look identical printed bare, and only one of them is
# worth marks.
case "${RANGE_OPENING:-}" in
    segs)
        echo "  the segments   ${RANGE_GIVEN}"
        echo "                 Confirmed live, and worth no marks: you were told."
        ;;
    candidates)
        echo "  candidates     ${RANGE_GIVEN}"
        echo "                 Some of these blocks hold nothing. Which ones are"
        echo "                 real is yours to establish, and it is worth marks."
        ;;
    count)
        echo "  the range      ${RANGE_GIVEN}"
        echo "                 The count tells you when to stop, not where to look."
        ;;
    dns)
        echo "  a starting point ${RANGE_GIVEN}"
        ;;
    prefix)
        echo "  the range      ${RANGE_GIVEN}"
        ;;
    *)
        echo "  the range      nothing. Work it out from the two lines above."
        ;;
esac
echo

if [ -n "${RANGE_DEPTH:-}" ] && [ "${RANGE_DEPTH:-0}" -ge 2 ]; then
    echo "== the way in =="
    echo "  This range is ${RANGE_DEPTH} layers deep. Somewhere on it is a service you"
    echo "  can do more with than describe, and at the end of that is a flag."
    echo "  Submit tokens with \`report flag <token>\`. Each layer you reach is"
    echo "  worth marks on its own, so a chain you got part way along still pays."
    echo
fi

# NOTHING BELOW ENUMERATES THE RANGE WHILE IT IS HEALTHY, and that is the point
# of this section rather than an omission from it. How many machines are out
# there is a scored finding: every host is worth marks, and a learner who knows
# the range holds seven of them knows when to stop scanning. So a healthy range
# reports one line, and the container names appear only where one of them is
# broken, which is the moment the learner needs them and the range has stopped
# being an exercise anyway.
echo "== oracle: is the range intact? =="
faults=0
faulty=""
for ctn in $( docker ps --format '{{.Names}}' | grep "^${CTN_PREFIX}" | grep -v netadmin_helper ); do
    token="${ctn#$CTN_PREFIX}"
    case "$token" in
        host[0-9]*)
            # A host is healthy when it holds an address and when every service
            # its profile claimed to start is still listening. The descriptor
            # files are the claim; netstat is the check. Neither the address nor
            # the port is printed, because both are graded findings.
            addr="$( docker exec "$ctn" ip -brief -4 addr show 2>/dev/null \
                     | awk '$1 != "lo" && $2 == "UP" && $3 != "" {print $3; exit}' )"
            if [ -z "$addr" ]; then
                faulty="${faulty}  ${token}: it holds no address\n"; faults=$(( faults + 1 )); continue
            fi
            bad="$( docker exec "$ctn" sh -c '
                n=0
                for f in /etc/minilabs/profile.d/*; do
                    [ -e "$f" ] || continue
                    b=$( basename "$f" ); proto=${b%%-*}; port=${b#*-}
                    flag=-tln; [ "$proto" = udp ] && flag=-uln
                    netstat $flag 2>/dev/null | grep -qE "[:.]$port +" || n=$(( n + 1 ))
                done
                echo $n' 2>/dev/null )"
            if [ "${bad:-1}" -ne 0 ]; then
                faulty="${faulty}  ${token}: ${bad} service(s) it started are no longer listening\n"
                faults=$(( faults + 1 ))
            fi
            ;;
        r[0-9]*)
            fwd="$( docker exec "$ctn" sysctl -n net.ipv4.ip_forward 2>/dev/null )"
            if [ "$fwd" != 1 ]; then
                faulty="${faulty}  ${token}: it is not forwarding\n"; faults=$(( faults + 1 ))
            fi
            ;;
        attacker)
            if ! docker exec "$ctn" ping -c 2 -W 2 "${att_gw:-0.0.0.0}" >/dev/null 2>&1; then
                faulty="${faulty}  ${token}: its own gateway does not reply\n"; faults=$(( faults + 1 ))
            fi
            ;;
    esac
done
if [ "$faults" -eq 0 ]; then
    echo "  Every machine this range spawned holds its address, and every service"
    echo "  that started is still listening. The range is intact."
else
    printf '%b' "$faulty"
    echo
    echo "  $faults fault(s). Regenerate draws a fresh range at the same tier."
fi
echo

# The tokens shell.sh accepts. Listing them names one container per machine, so
# the list is held back until Score has run, for the same reason the health check
# above says nothing while the range is healthy.
echo "== node tokens the Shell action accepts =="
if [ -f "$SCORED_MARKER" ] || [ "$faults" -gt 0 ]; then
    docker ps --format '{{.Names}}' | grep "^${CTN_PREFIX}" | sed "s/^${CTN_PREFIX}//" \
        | grep -v netadmin_helper | sort | paste -sd' ' - | sed 's/^/  /'
    echo "  Every step of the exercise runs on attacker. The rest are for looking"
    echo "  at why a probe did not land."
else
    echo "  attacker"
    echo "  The rest are listed once you have run Score. Naming them names one"
    echo "  container per machine, and how many machines are out there is one of"
    echo "  the things you are scored on."
fi
echo

# The point of a range is that it is replayed, so the thing worth showing between
# spawns is the run before this one. It is local and unsigned, exactly like the
# log it reads: collecting attempts for marking is out of scope until somebody
# asks for it.
if [ -s "$ATTEMPTS_LOG" ]; then
    echo "== your last few runs =="
    tail -5 "$ATTEMPTS_LOG" | while read -r ts rest; do
        set -- $rest
        line=""
        for kv in "$@"; do
            case "$kv" in
                seed=*|tier=*|shape=*|score=*|chain=*|elapsed=*)
                    line="${line}${line:+  }${kv}" ;;
            esac
        done
        printf '  %s  %s\n' "${ts%T*}" "$line"
    done
    echo
fi

echo "  Which addresses hold a host, what each one runs, and how far away each"
echo "  segment is are what you are scored on. None of it is printed here."
echo "  Reveal prints all of it, once you have run Score."
