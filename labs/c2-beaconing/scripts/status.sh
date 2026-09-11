#!/usr/bin/env bash
# Print the lab's state and its own success oracle, so the learner reads what
# changed without shelling into eight containers.
#
# It reads state and changes nothing. Two things it deliberately never prints:
# the controller's address, and which workstation the implant is on. Both are
# answers to the exercise, and a status action that handed them over would leave
# the learner nothing to find. The controller is reported by what it received,
# never by where it is.
#
# For the same reason the sections that report on the learner's egress policy
# stay closed until there is one. Before Part 3 the lab has no policy to report
# on, and a running count of what the controller is hearing would say how often
# the implant checks in, which is a measurement Part 2 asks the learner to take
# from their own capture.
#
# Every probe it runs comes from lib.sh, so what this prints and what selftest.sh
# asserts cannot drift apart.
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
for ctn in "$GW_CTN" "$WS1_CTN" "$WS2_CTN" "$WS3_CTN" "$EXT1_CTN" "$EXT2_CTN" "$SW_IN_CTN" "$SW_OUT_CTN"; do
    if running "$ctn"; then printf '  %-28s up\n' "$ctn"
    else                    printf '  %-28s DOWN\n' "$ctn"; fi
done

# ---------------------------------------------------------------------------
sec "The incident"
stage="$( beacon_stage )"
case "${stage:-}" in
    ''|0) echo "  the implant is not running. Reset the lab, or spawn it again." ;;
    *)    echo "  stage ${stage} of ${BEACON_MAX_STAGE}" ;;
esac
if beacon_running; then
    echo "  the implant is running. Advancing the incident changes how it behaves;"
    echo "  it does not stop or restart it."
else
    echo "  the implant is NOT running, so nothing is checking in."
fi

# ---------------------------------------------------------------------------
sec "The gateway's egress policy"
rules="$( nft_ruleset )"
if [ -z "$rules" ]; then
    echo "  none. The gateway forwards every packet between the two segments and"
    echo "  examines none of them, which is where Part 1 starts."
else
    echo "$rules" | sed 's/^/  /'
    pol="$( nft_forward_policy )"
    echo
    printf '  default policy at the forward hook: %s\n' "${pol:-none (no base chain at that hook)}"
    echo "  A chain whose default is accept blocks what its rules name. One whose"
    echo "  default is drop passes only what its rules name."
fi

if [ -z "$rules" ]; then
    sec "Where the lab stands"
    echo "  The sections that report on an egress policy stay closed until the"
    echo "  gateway has one, because until then there is nothing for them to"
    echo "  report on. Parts 1 and 2 are measured from your own capture, not from"
    echo "  here: this action is the oracle for Parts 3 to 5."
    echo
    echo "  Write your first rule on the gateway and run Status again."
    exit 0
fi

# ---------------------------------------------------------------------------
sec "What the controller received"
echo "  One line reaches the controller's record for every check-in that arrives."
echo "  The counts are over three windows, so a policy that has just started"
echo "  working shows as a long window that is full and a short one that is empty."
echo
c60="$( checkins_since 60 )"
c300="$( checkins_since 300 )"
c900="$( checkins_since 900 )"
ctot="$( checkins_total )"
age="$( last_checkin_age )"
printf '    last 60s   %s\n'  "$c60"
printf '    last 300s  %s\n'  "$c300"
printf '    last 900s  %s\n'  "$c900"
printf '    total      %s\n'  "$ctot"
if [ -n "$age" ]; then
    printf '    last one   %ss ago\n' "$age"
else
    printf '    last one   never\n'
fi

# ---------------------------------------------------------------------------
sec "What still works, from ws1"
echo "  Three services on the outside segment are legitimate and have to keep"
echo "  answering. 200 is the service replying; 000 is curl giving up with no"
echo "  reply at all, which is what a dropped packet looks like to a client."
echo
m="$( mirror_code ws1 )"; d="$( docs_code ws1 )"; h="$( health_code ws1 )"
printf '    package mirror        %s\n' "$m"
printf '    documentation site    %s\n' "$d"
printf '    monitoring endpoint   %s\n' "$h"

# ---------------------------------------------------------------------------
sec "Where the lab stands"

stopped=no
if [ "$c60" -eq 0 ] && { [ -z "$age" ] || [ "$age" -ge 60 ]; }; then stopped=yes; fi
mark "$stopped"
if [ -n "$age" ]; then
    printf 'the controller has heard nothing for %ss\n' "$age"
else
    printf 'the controller has never heard anything\n'
fi

alive=no
if [ "$m" = 200 ] && [ "$d" = 200 ] && [ "$h" = 200 ]; then alive=yes; fi
mark "$alive"; echo "all three legitimate services still answer ws1"

pol="$( nft_forward_policy )"
allow=no
[ "$pol" = drop ] && allow=yes
mark "$allow"; echo "the policy is an allowlist: the forward chain's default is drop"

held=no
if [ "$allow" = yes ] && [ "$stopped" = yes ] && [ "$alive" = yes ] && [ "${stage:-1}" -ge 3 ]; then
    held=yes
fi
mark "$held"; echo "the allowlist is holding at stage ${stage:-1}, with the controller moved"

echo
echo "  The first two marks together are what containment means here. Either one"
echo "  on its own is easy: a gateway that forwards nothing stops the check-ins,"
echo "  and a gateway with no policy keeps every service answering."
