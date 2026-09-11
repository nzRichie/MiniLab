#!/usr/bin/env bash
# Print the command that opens a shell on every node in the lab, or open one of
# them. The routers are configured only over vtysh, so a router line runs vtysh;
# the hosts and the two RPKI containers get a plain shell.
#
# The TUI streams a script's output non-interactively and cannot host a PTY, so
# with no terminal attached this prints one line per node and the learner pastes
# the one they want into their own terminal. Given a node name as $1 from a real
# terminal it opens that shell instead.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROUTERS="as1 as2 as3 as4 as5 as6"
HOSTS="victim client2 client3 client4 client5 attacker"
RPKI="rir validator"
ROLES="$ROUTERS $HOSTS $RPKI"

running="$( docker ps --format '{{.Names}}' 2>/dev/null )"

# Marks the nodes whose container is not up, so a learner who has not spawned
# the lab (or has torn it down) reads why the line they are about to paste fails.
state_of() {   # <container>
    grep -qxF "$1" <<< "$running" || echo "   (not running)"
}

# <node> -> the container it lives in, and the command a shell on it runs.
resolve() {
    case "$1" in
        as[1-6])   ctn="$( router_ctn "${1#as}" )"; cmd=vtysh ;;
        victim)    ctn="$( host_ctn 1 )"; cmd=bash ;;
        client2)   ctn="$( host_ctn 2 )"; cmd=bash ;;
        client3)   ctn="$( host_ctn 3 )"; cmd=bash ;;
        client4)   ctn="$( host_ctn 4 )"; cmd=bash ;;
        client5)   ctn="$( host_ctn 5 )"; cmd=bash ;;
        attacker)  ctn="$( host_ctn 6 )"; cmd=bash ;;
        # The RIR carries krillc with its server and token already in the
        # environment, so `krillc roas list --ca AS1` works as typed once inside.
        rir)       ctn="$RIR_CTN";       cmd=bash ;;
        validator) ctn="$VALIDATOR_CTN"; cmd=sh ;;
        *)         return 1 ;;
    esac
}

if [ $# -ge 1 ]; then
    resolve "$1" || {
        echo "unknown node '$1'; expected one of: $ROLES" >&2
        exit 1
    }
    if [ -t 0 ] && [ -t 1 ]; then
        exec docker exec -it "$ctn" "$cmd"
    fi
    echo "Open a terminal and run:"
    echo "    docker exec -it $ctn $cmd"
    exit 0
fi

ctn_width=0
for role in $ROLES; do
    resolve "$role"
    if [ ${#ctn} -gt "$ctn_width" ]; then ctn_width=${#ctn}; fi
done

group() {   # <heading> <node>...
    local heading="$1"; shift
    echo "  $heading"
    local role
    for role in "$@"; do
        resolve "$role"
        printf '    %-10s docker exec -it %-*s %s%s\n' \
            "$role" "$ctn_width" "$ctn" "$cmd" "$( state_of "$ctn" )"
    done
    echo
}

echo "Open a terminal and run the line for the node you want."
echo
group "routers (vtysh; as6 is the attacker's, as1 the victim's)" $ROUTERS
group "hosts (a plain shell; the ping and traceroute work is here)" $HOSTS
group "RPKI (rir runs Krill and has krillc, validator runs Routinator)" $RPKI
