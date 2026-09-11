#!/usr/bin/env bash
# Return the lab to its clean state at spawn WITHOUT tearing it down: blank every
# router, and put every host back to its own address with no default route.
#
# A learner who has tangled their configuration is back at a network where nothing
# is configured and every part of the handout can be worked through again from the
# start. This is a bigger undo than the other labs' reset, because in this lab
# everything is the learner's configuration, so "baseline" means blank.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "[reset] blanking every router"
for r in "${ROUTERS[@]}"; do
    # The starter script restarts FRR against an empty frr.conf, so it removes the
    # OSPF stanza, every address and every cost without needing to know which of
    # them the learner typed.
    docker exec "$( router_ctn "$r" )" "/home/${r}.sh" >/dev/null 2>&1 \
        || echo "[reset] WARNING: $( uc "$r" ) did not blank cleanly; check status.sh" >&2
done

echo "[reset] returning every host to its own address, with no default route"
for r in "${ROUTERS[@]}"; do
    docker exec "$( host_ctn "$r" )" /home/host-setup.sh \
        "$( host_ip "$r" )/${HOST_PREFIXLEN}" "$( host_gw "$r" )" "$( host_banner "$r" )" \
        >/dev/null 2>&1 \
        || echo "[reset] WARNING: $( host_ctn "$r" ) did not reset cleanly" >&2
done

echo "[reset] baseline restored: no addresses, no OSPF, no default routes."
echo "[reset] The per-link delays are untouched -- they belong to the wiring, not"
echo "[reset] to anything the learner configures, and survive until teardown."
