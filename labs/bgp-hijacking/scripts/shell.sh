#!/usr/bin/env bash
# Shell into a lab node. Usage: shell.sh <node>   (default: as6, the attacker router)
#   Routers (control plane): as1 as2 as3 as4 as5 as6   -> drop straight into vtysh
#   Hosts   (bash side):      victim client2 client3 client4 client5 attacker
#   RPKI:                     rir (Krill, has krillc) and validator (Routinator)
# The routers are configured only over vtysh, so a router shell opens vtysh; the
# hosts and the RPKI containers open a plain shell. The current miniManager engine
# streams non-interactively and cannot host a live shell, so with no TTY we print
# the command for the learner to run in their own terminal.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

node="${1:-as6}"
case "$node" in
    as[1-6])
        ctn="$( router_ctn "${node#as}" )"; cmd=(vtysh) ;;
    victim)    ctn="$( host_ctn 1 )"; cmd=(bash) ;;
    attacker)  ctn="$( host_ctn 6 )"; cmd=(bash) ;;
    client2)   ctn="$( host_ctn 2 )"; cmd=(bash) ;;
    client3)   ctn="$( host_ctn 3 )"; cmd=(bash) ;;
    client4)   ctn="$( host_ctn 4 )"; cmd=(bash) ;;
    client5)   ctn="$( host_ctn 5 )"; cmd=(bash) ;;
    # The RIR carries krillc with its server and token already in the environment,
    # so `krillc roas list --ca AS1` works as typed once you are inside.
    rir)       ctn="$RIR_CTN";       cmd=(bash) ;;
    validator) ctn="$VALIDATOR_CTN"; cmd=(sh) ;;
    *)
        echo "unknown node '$node'. Choose: as1..as6, victim, client2..client5, attacker, rir, validator" >&2
        exit 1 ;;
esac

if [ -t 0 ] && [ -t 1 ]; then
    exec docker exec -it "$ctn" "${cmd[@]}"
else
    echo "Open a terminal and run:"
    echo "    docker exec -it $ctn ${cmd[*]}"
fi
