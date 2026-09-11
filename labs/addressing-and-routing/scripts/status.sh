#!/usr/bin/env bash
# Show what the lab is doing, and its success oracle.
#
# The oracle is the pairwise reachability matrix at the bottom: every host
# reaching every other host is what "done" means, and it is the one fact a script
# can read without a human judging a configuration. The four stages above it exist
# because a single red matrix says nothing about which of thirty commands was
# wrong, and this lab is the one where the learner has not yet built the habit of
# working that out from `ip addr show` and `ip route show` alone.
#
# Nothing here configures anything. It reads state and prints it.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

pass=0; fail=0
mark() {   # <ok?> <text>
    if [ "$1" = "yes" ]; then pass=$((pass+1)); printf '  [ ok ] %s\n' "$2"
    else                      fail=$((fail+1)); printf '  [    ] %s\n' "$2"; fi
}

echo "== containers =="
docker ps --filter "name=${AS}_L3_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -v netadmin_helper
echo

echo "== the addressing this lab asks for =="
printf '  %-24s %s\n' "West Net   (${SW_WEST})" "$WEST_SUBNET"
printf '  %-24s %s\n' "Middle Net (${SW_MID})"  "$MID_SUBNET"
printf '  %-24s %s\n' "East Net   (${SW_EAST})" "$EAST_SUBNET"
echo

# ---------------------------------------------------------------------------
echo "== stage 1: ten interfaces, each up and carrying its address =="
for row in "${LINKS[@]}"; do
    set -- $row
    dev="$1"; dev_if="$2"; want="$4/${PREFIXLEN}"
    got="$( addr_on "$dev" "$dev_if" )"
    if if_is_up "$dev" "$dev_if"; then up="up"; else up="DOWN"; fi
    if [ "$got" = "$want" ] && [ "$up" = "up" ]; then
        mark yes "$( printf '%-12s %-9s %s' "$dev" "$dev_if" "$want" )"
    else
        mark no  "$( printf '%-12s %-9s %-18s (want %s, up)' \
                     "$dev" "$dev_if" "${got:-no address} ${up}" "$want" )"
    fi
done
echo

# ---------------------------------------------------------------------------
echo "== stage 2: every device reaches every other device on its own subnet =="
# One direction per pair. A reply proves both directions worked, because the
# reply is a packet travelling the other way.
check_subnet() {   # <label> <dev:addr> ...
    local label="$1"; shift
    local pairs=( "$@" ) a b
    local i j
    for (( i = 0; i < ${#pairs[@]}; i++ )); do
        for (( j = i + 1; j < ${#pairs[@]}; j++ )); do
            a="${pairs[$i]%%:*}"; b="${pairs[$j]}"
            if can_ping "$a" "${b#*:}"; then
                mark yes "$( printf '%-11s %-12s -> %-12s %s' "$label" "$a" "${b%%:*}" "${b#*:}" )"
            else
                mark no  "$( printf '%-11s %-12s -> %-12s %s' "$label" "$a" "${b%%:*}" "${b#*:}" )"
            fi
        done
    done
}
check_subnet "West Net"   "west-1:$IP_WEST1" "west-2:$IP_WEST2" "west-router:$IP_WR_WEST"
check_subnet "Middle Net" "mid-1:$IP_MID1" "mid-2:$IP_MID2" \
                          "west-router:$IP_WR_MID" "east-router:$IP_ER_MID"
check_subnet "East Net"   "east-1:$IP_EAST1" "east-2:$IP_EAST2" "east-router:$IP_ER_EAST"
echo

# ---------------------------------------------------------------------------
echo "== stage 3: a default route on each host, and none on either router =="
for h in "${HOSTS[@]}"; do
    gw="$( default_route_of "$h" )"
    if [ -z "$gw" ]; then
        mark no "$( printf '%-12s no default route' "$h" )"
        continue
    fi
    # The gateway has to be an address on the host's own subnet: a host can only
    # send a packet to a first hop it can reach without a router.
    own="$( host_ip "$h" )"
    if [ "${gw%.*}" = "${own%.*}" ]; then
        mark yes "$( printf '%-12s default via %s' "$h" "$gw" )"
    else
        mark no  "$( printf '%-12s default via %s, which is not on this host'"'"'s subnet' "$h" "$gw" )"
    fi
done
for r in "${ROUTERS[@]}"; do
    gw="$( default_route_of "$r" )"
    if [ -z "$gw" ]; then
        mark yes "$( printf '%-12s no default route (correct: a router in this lab needs none)' "$r" )"
    else
        mark no  "$( printf '%-12s has a default route via %s; the two routers will bounce' "$r" "$gw" )"
        mark no  "$( printf '%-12s packets for any address outside this lab back and forth' "" )"
    fi
done
echo

# ---------------------------------------------------------------------------
echo "== stage 4: the oracle, every host reaches every host =="
tmp="$( mktemp -d )"
trap 'rm -rf "$tmp"' EXIT
# Six sources in parallel, five pings each. Serially this is thirty seconds of
# waiting on a broken network; in parallel it is five.
for src in "${HOSTS[@]}"; do
    (
        for dst in "${HOSTS[@]}"; do
            [ "$src" = "$dst" ] && continue
            if can_ping "$src" "$( host_ip "$dst" )"; then
                echo "$src $dst ok"
            else
                echo "$src $dst XX"
            fi
        done
    ) > "$tmp/$src" &
done
wait

printf '  %-12s' "from \\ to"
for dst in "${HOSTS[@]}"; do printf ' %-7s' "$dst"; done
echo
reach_ok=0; reach_total=0
for src in "${HOSTS[@]}"; do
    printf '  %-12s' "$src"
    for dst in "${HOSTS[@]}"; do
        if [ "$src" = "$dst" ]; then printf ' %-7s' "-"; continue; fi
        res="$( awk -v d="$dst" '$2 == d { print $3 }' "$tmp/$src" )"
        printf ' %-7s' "$res"
        reach_total=$((reach_total+1))
        [ "$res" = "ok" ] && reach_ok=$((reach_ok+1))
    done
    echo
done
echo
printf '  %d of %d host pairs reachable\n' "$reach_ok" "$reach_total"
echo

# ---------------------------------------------------------------------------
echo "== where the network is =="
if [ "$reach_ok" -eq "$reach_total" ] && [ "$fail" -eq 0 ]; then
    echo "  DONE        every host reaches every other host, and all three stages above"
    echo "              agree with the addressing plan"
elif [ "$reach_ok" -eq "$reach_total" ]; then
    printf '  REACHABLE   every host reaches every other host, but %d check(s) above\n' "$fail"
    echo "              disagree with the addressing plan; read the unticked lines"
elif [ "$fail" -eq 0 ]; then
    printf '  ROUTING GAP every interface is addressed, every subnet is reachable from\n'
    printf '              inside itself, and every host has a first hop off its own\n'
    printf '              subnet, and %d of %d host pairs still cannot reach each other.\n' \
        "$((reach_total - reach_ok))" "$reach_total"
    echo "              Nothing checked above says anything about what the two routers"
    echo "              know; that is the only part of the network still unexamined."
else
    printf '  BUILDING    %d of %d checks above pass. The first unticked line is the\n' \
        "$pass" "$((pass+fail))"
    echo "              earliest thing to fix, because every later stage depends on it."
fi
