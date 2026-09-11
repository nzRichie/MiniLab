#!/usr/bin/env bash
# Show what the lab is doing without shelling in: the containers, what each router
# has been given, how many OSPF adjacencies it has reached and over which
# interfaces, the cost on the link Part 3 is about, how each host pair fares, and
# which host actually replies at the far end of the pair Part 3 measures.
#
# This is the lab's own report card. On a freshly spawned lab it is almost all
# blank, which is correct: nothing is configured yet. It fills in as the learner
# works through the four parts.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${LAB_FILTER}" --format 'table {{.Names}}\t{{.Status}}' | sort
echo

echo "== router addressing =="
printf '  %-6s %-18s %-22s %s\n' "router" "loopback" "host-facing" "router-to-router"
for r in "${ROUTERS[@]}"; do
    lo="$( docker exec "$( router_ctn "$r" )" sh -c \
        "ip -4 -o addr show lo scope global 2>/dev/null | awk '{print \$4}' | tr '\n' ' '" 2>/dev/null )"
    hf="$( docker exec "$( router_ctn "$r" )" sh -c \
        "ip -4 -o addr show ${HOST_IF_ROUTER} 2>/dev/null | awk '{print \$4}' | tr '\n' ' '" 2>/dev/null )"
    n=0
    while read -r peer _ _ _ _; do
        [ -z "$peer" ] && continue
        a="$( docker exec "$( router_ctn "$r" )" sh -c \
            "ip -4 -o addr show $( peer_if "$peer" ) 2>/dev/null | awk '{print \$4}'" 2>/dev/null )"
        [ -n "$a" ] && n=$(( n + 1 ))
    done < <( links_of "$r" )
    printf '  %-6s %-18s %-22s %s\n' "$( uc "$r" )" "${lo:--}" "${hf:--}" \
           "${n}/$( peer_count "$r" ) addressed"
done
echo

echo "== OSPF adjacencies =="
total_full=0; total_want=0
for r in "${ROUTERS[@]}"; do
    full="$( ospf_full_neighbours "$( router_ctn "$r" )" )"
    want="$( peer_count "$r" )"
    total_full=$(( total_full + full )); total_want=$(( total_want + want ))
    printf '  %-6s %s of %s links Full\n' "$( uc "$r" )" "${full:-0}" "$want"
    # Any neighbour not yet Full is named, with the interface it is on: a count
    # that is one short says something is wrong, this says where.
    while read -r rid state iface; do
        [ -z "$rid" ] && continue
        case "$state" in Full*) ;; *) printf '      %-16s %-12s on %s\n' "$rid" "$state" "$iface" ;; esac
    done < <( ospf_neighbour_detail "$( router_ctn "$r" )" )
done
echo "  total: ${total_full} of ${total_want} router-to-router adjacencies are Full"
echo

echo "== OSPF packets arriving on the host links (Part 4 drives this to zero) =="
hello_total=0
for r in "${ROUTERS[@]}"; do
    # 22 seconds, because hellos are 10 seconds apart and a window that is barely
    # one interval long reports zero on a link that is sending normally.
    n="$( hellos_on_host_link "$r" 22 )"
    hello_total=$(( hello_total + n ))
    printf '  %-6s %s packet(s) in 22 s on its host link\n' "$( uc "$r" )" "$n"
done
if [ "$hello_total" -eq 0 ]; then
    echo "  none: no router is sending OSPF where only a host is listening"
fi
echo

echo "== the link Part 3 is about: $( uc "$SLOW_LINK_A" ) <-> $( uc "$SLOW_LINK_B" ) =="
ca="$( ospf_if_cost "$( router_ctn "$SLOW_LINK_A" )" "$( peer_if "$SLOW_LINK_B" )" )"
cb="$( ospf_if_cost "$( router_ctn "$SLOW_LINK_B" )" "$( peer_if "$SLOW_LINK_A" )" )"
printf '  OSPF cost: %s side %s, %s side %s\n' \
    "$( uc "$SLOW_LINK_A" )" "${ca:--}" "$( uc "$SLOW_LINK_B" )" "${cb:--}"
echo

echo "== $( uc "$TE_SRC" )'s host to $( uc "$TE_DST" )'s host =="
rtt="$( rtt_ms "$TE_SRC" "$( host_ip "$TE_DST" )" )"
if [ -n "$rtt" ]; then
    echo "  round-trip time: ${rtt} ms"
    echo "  through routers: $( path_routers "$TE_SRC" "$( host_ip "$TE_DST" )" )"
else
    echo "  no reply (the two hosts cannot reach each other yet)"
fi
echo

echo "== host-to-host reachability =="
ok=0; fail=0; failed=()
for a in "${ROUTERS[@]}"; do
    for b in "${ROUTERS[@]}"; do
        [ "$a" = "$b" ] && continue
        if docker exec "$( host_ctn "$a" )" ping -c 2 -W 2 -q "$( host_ip "$b" )" >/dev/null 2>&1
        then ok=$(( ok + 1 ))
        else fail=$(( fail + 1 )); failed+=("$( uc "$a" )->$( uc "$b" )")
        fi
    done
done
echo "  ${ok} of $(( ok + fail )) ordered host pairs can reach each other"
[ "$fail" -gt 0 ] && echo "  not reaching: ${failed[*]}"
echo

echo "== which host replies at the far end =="
# ping proves something replied; this proves the packet reached the host the
# addressing plan says owns that address.
for r in "${ROUTERS[@]}"; do
    ans="$( who_answers "$TE_SRC" "$( host_ip "$r" )" )"
    [ "$r" = "$TE_SRC" ] && continue
    printf '  %s host asked %-14s -> %s\n' "$( uc "$TE_SRC" )" "$( host_ip "$r" )" "${ans:-<no reply>}"
done
echo

if [ "$total_full" -eq "$total_want" ] && [ "$fail" -eq 0 ]; then
    if [ "$hello_total" -eq 0 ]; then
        echo "== verdict: configured -- every adjacency up, every host pair reaching, host links quiet =="
    else
        echo "== verdict: routing works, but OSPF is still being sent on the host links (Part 4) =="
    fi
else
    echo "== verdict: not converged yet -- see the adjacency and reachability counts above =="
fi
