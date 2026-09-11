#!/usr/bin/env bash
# Shared definitions for the OSPF routing lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, router names and
# location numbers, every address, every interface name, and the per-link one-way
# delay. Every other script sources it; never hardcode any of these in a second
# place. The default_config/*.sh and solution/*
# scripts repeat some addresses because they run inside containers, where they
# cannot source this file; they cite this file as the source.
#
# Topology: five FRR routers in a pentagon with one chord, each with one host.
# Every link between them is a point-to-point /30 veth; there is no switch and no
# OVS anywhere in this lab.
#
#                       LOND (1)
#                      /        \
#           109.0.5/30            109.0.1/30
#                    /              \
#              PARI (2) --109.0.6/30-- NEWY (4)
#                    \                  \
#           109.0.4/30                    109.0.2/30   <- the 100 ms link
#                      \                    \
#                       TRGA (3) --109.0.3/30-- ZURI (5)
#
# Six links, and PARI and NEWY carry three each. The shape is what the lab is
# built on:
#
#   * LOND reaches ZURI over two paths: LOND-NEWY-ZURI (two hops) and
#     LOND-PARI-TRGA-ZURI (three hops). At equal cost OSPF takes the two-hop path,
#     which is the one carrying the 100 ms delay, so the shortest path is the slow
#     path until the learner changes a cost. That is Part 3.
#   * The chord closes a four-node cycle (PARI-NEWY-ZURI-TRGA), and in a cycle of
#     four the two opposite pairs each have two equal-length paths. So PARI-to-ZURI
#     and NEWY-to-TRGA arrive as equal-cost pairs and OSPF installs both next hops.
#     Raising the cost of the 100 ms link in Part 3 breaks both ties as a side
#     effect, which is why the route tables get SHORTER after the cost change.
#
# Addresses follow the Waikato COMPX304 assignment's plan, so a learner who meets
# that assignment later reads the same arithmetic:
#
#   host subnet    109.[100+Y].0.0/24   host .1, router .2
#   loopback       109.[150+Y].0.1/32
#   router link    109.0.N.0/30         lower location number takes .1
#
# where Y is the router's location number (LOND 1, PARI 2, TRGA 3, NEWY 4,
# ZURI 5) and N is the link number in LINKS below.

AS=109
LAYER=L3
DC=OSPF           # the lab tag; every container name carries _${LAYER}_${DC}_ so
                  # one grep selects the whole lab.

# Routers, in location-number order. The name is the container suffix, the shell.sh
# selector, and the label in the topology figure; the number drives every address.
ROUTERS=(lond pari trga newy zuri)
declare -A LOC
LOC[lond]=1; LOC[pari]=2; LOC[trga]=3; LOC[newy]=4; LOC[zuri]=5

# Upper-case form, used in interface names (port_NEWY) and in handout prose.
uc() { echo "${1^^}"; }

# ---------------------------------------------------------------------------
# Derived addressing. Nothing below is typed twice.
host_subnet()   { echo "${AS}.$(( 100 + ${LOC[$1]} )).0.0/24"; }
host_ip()       { echo "${AS}.$(( 100 + ${LOC[$1]} )).0.1"; }     # the host itself
host_gw()       { echo "${AS}.$(( 100 + ${LOC[$1]} )).0.2"; }     # the router's leg
loopback_ip()   { echo "${AS}.$(( 150 + ${LOC[$1]} )).0.1"; }
router_id()     { loopback_ip "$1"; }                             # router-id = loopback

HOST_PREFIXLEN=24
LOOPBACK_PREFIXLEN=32
LINK_PREFIXLEN=30

# ---------------------------------------------------------------------------
# The six router-to-router links. Fields:
#
#   <a> <b> <a_ip> <b_ip> <subnet> <one-way delay ms>
#
# with a the router of lower location number, which always takes .1. The delay is
# applied by spawn.sh at BOTH ends of the link, so the round-trip a learner
# measures with ping is twice the number here plus scheduling noise.
#
# The 100 ms on newy-zuri is the whole of Part 3: it sits on the two-hop path
# between LOND and ZURI, so the path OSPF picks by default is fourteen times
# slower than the three-hop path around the other side (105 ms one way against
# 15 ms). The other five delays are small and differ from each other so that the
# per-link measurement in Part 3 produces a table with something in it, rather
# than five identical numbers.
LINKS=(
    "lond newy 109.0.1.1 109.0.1.2 109.0.1.0/30   5"
    "newy zuri 109.0.2.1 109.0.2.2 109.0.2.0/30 100"
    "trga zuri 109.0.3.1 109.0.3.2 109.0.3.0/30   5"
    "pari trga 109.0.4.1 109.0.4.2 109.0.4.0/30   5"
    "lond pari 109.0.5.1 109.0.5.2 109.0.5.0/30   5"
    "pari newy 109.0.6.1 109.0.6.2 109.0.6.0/30  10"
)

# The link the lab is about, and the cost the learner ends up putting on it.
#
# The threshold is 20: the two-hop path costs 10 + X and the three-hop path costs
# 30, so the path moves as soon as X exceeds 20. 100 is well past it, which means
# the learner's arithmetic in Part 3 does not have to be exactly right for the
# result to be unambiguous, and a round number is easier to spot in `show ip ospf
# interface` output than 21 would be.
SLOW_LINK_A=newy
SLOW_LINK_B=zuri
SLOW_LINK_COST=100
DEFAULT_OSPF_COST=10          # FRR's cost on an interface whose bandwidth it cannot read

# The pair whose path the cost change moves, and the router the moved path runs
# through. Used by the handout, status.sh and selftest.sh; stated in one place so
# the three cannot disagree.
TE_SRC=lond                   # measure from this host ...
TE_DST=zuri                   # ... to this one
TE_PATH_BEFORE=(newy)         # routers between them at equal cost (the slow path)
TE_PATH_AFTER=(pari trga)     # routers between them once the cost is raised

# ---------------------------------------------------------------------------
# The single OSPF area every router in this lab puts every one of its subnets in.
# Five routers is far below the size at which dividing a network into areas buys
# anything, so there is one area and it is the backbone.
OSPF_AREA="0.0.0.0"

# The identity banner each host serves on port 80, naming itself. A curl that
# crosses the network therefore reports WHICH host received the request, which is
# a stronger check than ping: ping says something replied, the banner says the
# packet reached the host the addressing plan says it should have.
host_banner() { echo "$( uc "$1" ) host at $( host_ip "$1" )"; }

# ---------------------------------------------------------------------------
# Container and interface names. Containers follow the platform convention
# <AS>_<LAYER>_<DC>_<role>.
router_ctn() { echo "${AS}_${LAYER}_${DC}_$1"; }
host_ctn()   { echo "${AS}_${LAYER}_${DC}_$1-host"; }

# A router's interface toward another router is port_<PEER>, the same naming the
# Waikato assignment uses. Its interface toward its own host is `host`, and the
# host's interface toward the router is `router`.
peer_if()      { echo "port_$( uc "$1" )"; }
HOST_IF_ROUTER="host"
HOST_IF_HOST="router"

LAB_FILTER="_${LAYER}_${DC}_"

NODE_IMAGE="d_node_ospf"
HOST_IMAGE="$NODE_IMAGE"      # helper_start uses HOST_IMAGE; one image serves both roles

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# Convenience iterators, so no other script re-parses LINKS by hand.

# Every router-to-router link as "<a> <b> <a_ip> <b_ip> <subnet> <delay>".
each_link() { printf '%s\n' "${LINKS[@]}"; }

# The links one router terminates, printed as "<peer> <own_ip> <peer_ip> <subnet> <delay>".
links_of() {
    local me="$1" a b aip bip subnet delay
    while read -r a b aip bip subnet delay; do
        [ -z "$a" ] && continue
        if   [ "$a" = "$me" ]; then echo "$b $aip $bip $subnet $delay"
        elif [ "$b" = "$me" ]; then echo "$a $bip $aip $subnet $delay"
        fi
    done < <( each_link )
}

# How many router-to-router links a router has, which is how many OSPF neighbours
# it must end up with once the network is converged.
peer_count() { links_of "$1" | grep -c . ; }

# One link, addressed from one end: the address <router> holds on its link to
# <peer>, and the subnet that link is on. So a script naming a specific address in
# the handout ("ping 109.0.3.2") reads it off the plan rather than repeating it.
link_end()    { links_of "$1" | awk -v p="$2" '$1==p {print $2; exit}'; }
link_subnet() { links_of "$1" | awk -v p="$2" '$1==p {print $4; exit}'; }

# ---------------------------------------------------------------------------
# Image preflight, called by spawn.sh before the first `docker run`.
#
# One image serves routers and hosts alike. The two roles differ only in what is
# started inside them: a router runs FRR from birth, a host runs nothing until
# somebody starts something. Building one image rather than two halves the first
# spawn and, more to the point, makes the attack in Part 4 honest -- the attacker
# is not a special container, it is the same image as every other host with a
# daemon started by hand.
#
# Rebuilt when anything under image/ is newer than the built image, so an edit to
# the Dockerfile reaches a machine that already built it once.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

ensure_images() {
    local dir="$LAB_DIR/image"
    if ! docker image inspect "$NODE_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] building $NODE_IMAGE from image/ (first run only)"
        docker build -t "$NODE_IMAGE" "$dir" || { echo "failed to build $NODE_IMAGE" >&2; return 1; }
    elif image_older_than_source "$NODE_IMAGE" "$dir"; then
        echo "[spawn] rebuilding $NODE_IMAGE: image/ changed since it was built"
        docker build -t "$NODE_IMAGE" "$dir" || { echo "failed to rebuild $NODE_IMAGE" >&2; return 1; }
    fi
}

# ---------------------------------------------------------------------------
# Privileged host networking, performed from a helper container.
#
# Wiring a lab needs privileges a learner's account will not have: CAP_NET_ADMIN
# to create a veth pair, and CAP_SYS_ADMIN to enter a container's network
# namespace and rename the interface inside it. Rather than require root on the
# host, a throwaway --privileged container holds them.
#
# The helper keeps a network namespace of its own (--network=none). Both ends of
# every veth pair are moved out into lab containers, so the namespace the pair is
# created in never matters. Asking for the host's namespace (--network=host) only
# breaks the helper under a rootless daemon, where that namespace belongs to a
# user namespace the helper holds no privilege in and every `ip link add` returns
# EPERM. --pid=host stays: it is what makes each lab container's
# /proc/<pid>/ns/net reachable for the moves.
#
# Renames run through `nsenter --net`, not `ip netns exec`. iproute2 remounts /sys
# on every namespace switch and a user namespace forbids that, while the rename
# itself is pure netlink and needs no sysfs at all.
HELPER_CTN="0_${LAYER}_${DC}_netadmin"

helper_start() {
    docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true
    docker run -d --rm --init --name "$HELPER_CTN" \
        --privileged --network=none --pid=host \
        "$HOST_IMAGE" sleep 600 >/dev/null
    for _ in $(seq 1 40); do
        if docker exec "$HELPER_CTN" true >/dev/null 2>&1; then return 0; fi
        sleep 0.25
    done
    echo "helper container $HELPER_CTN did not become ready" >&2
    return 1
}
helper()      { docker exec "$HELPER_CTN" "$@"; }
helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }

# Attach a netem delay to one interface inside one container.
#
# Run from the helper rather than from the target container, because the first
# netem qdisc on a machine has to autoload the kernel's sch_netem module, and the
# kernel grants an autoload only to a process with CAP_SYS_MODULE in the initial
# user namespace. The helper is --privileged and, under a rootful daemon, holds
# it; a plain lab container with --cap-add=NET_ADMIN does not, and the qdisc add
# comes back "Specified qdisc kind is unknown".
#
# Under a ROOTLESS daemon nothing in a container holds that capability, so the
# module has to be resident before the lab spawns. spawn.sh checks and says so.
helper_netem() {   # <pid> <ifname> <delay ms>
    helper nsenter --net="/proc/$1/ns/net" \
        tc qdisc replace dev "$2" root netem delay "${3}ms"
}

# Is sch_netem usable? Tried once from the helper, on the helper's own loopback,
# which is also what loads the module for the rest of the spawn. Loopback rather
# than a fresh dummy interface, so that a machine without the `dummy` module does
# not report netem missing when netem is fine.
netem_available() {
    helper sh -c '
        rc=1
        tc qdisc add dev lo root netem delay 1ms >/dev/null 2>&1 && rc=0
        tc qdisc del dev lo root >/dev/null 2>&1
        exit $rc'
}

# ---------------------------------------------------------------------------
# Waits and oracles.

# FRR takes a moment to open its vty socket. Bounded, so a broken image fails
# loudly instead of hanging a spawn.
wait_for_vtysh() {
    local ctn="$1"
    for _ in $(seq 1 60); do
        if docker exec "$ctn" vtysh -c 'show version' >/dev/null 2>&1; then return 0; fi
        sleep 0.5
    done
    echo "vtysh never came up in $ctn" >&2
    return 1
}

# How many OSPF neighbours a router currently has in state Full. The JSON parse
# runs INSIDE the container (python3 ships there with frr-pythontools), so the
# host needs no python. This is the control-plane oracle the whole lab reads:
# a router with fewer Full neighbours than it has links has an adjacency down.
#
# The state field is `nbrState` and its value carries the DR role as well as the
# state ("Full/DR", "Full/Backup", "Full/DROther"), so this matches on the prefix
# rather than on equality. `show ip ospf neighbor json` keys the object by
# neighbour router-id and gives each a LIST, because one router can be reached
# over more than one interface.
ospf_full_neighbours() {
    local ctn="$1"
    docker exec "$ctn" sh -c "vtysh -c 'show ip ospf neighbor json' 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(0); sys.exit(0)
n=0
for entries in d.get(\"neighbors\",{}).values():
    if not isinstance(entries,list): entries=[entries]
    for e in entries:
        if str(e.get(\"nbrState\",\"\")).startswith(\"Full\"): n+=1
print(n)'" 2>/dev/null || echo 0
}

# Every OSPF neighbour a router has, whatever state it is in, as
# "<router-id> <state> <interface>" per line. status.sh prints this so a learner
# who has an adjacency stuck in Init or ExStart sees which one and where, rather
# than only a count that is one short.
ospf_neighbour_detail() {
    local ctn="$1"
    docker exec "$ctn" sh -c "vtysh -c 'show ip ospf neighbor json' 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for rid,entries in sorted(d.get(\"neighbors\",{}).items()):
    if not isinstance(entries,list): entries=[entries]
    for e in entries:
        print(rid, e.get(\"nbrState\",\"?\"), str(e.get(\"ifaceName\",\"?\")).split(\":\")[0])'" 2>/dev/null
}

# Every next hop a router would use for a destination, as a space-separated list
# of gateway addresses, read from zebra rather than from OSPF, so it is what the
# forwarding plane will actually do. Two entries means equal-cost multipath.
route_nexthops() {
    local ctn="$1" dest="$2"
    docker exec "$ctn" sh -c "vtysh -c 'show ip route ${dest} json' 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
out=[]
for routes in d.values():
    for r in routes:
        if not r.get(\"selected\"): continue
        for nh in r.get(\"nexthops\",[]):
            ip=nh.get(\"ip\")
            if ip and ip not in out: out.append(ip)
print(\" \".join(out))'" 2>/dev/null
}

# The OSPF cost a router has on one interface, as FRR reports it.
ospf_if_cost() {
    local ctn="$1" ifname="$2"
    docker exec "$ctn" sh -c "vtysh -c 'show ip ospf interface ${ifname} json' 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for k,v in d.get(\"interfaces\",d).items():
    if isinstance(v,dict) and \"cost\" in v: print(v[\"cost\"]); break'" 2>/dev/null
}

# Does this router hold a route to a prefix at all? Prints the route's protocol
# ("ospf", "connected", ...) or nothing. Used to watch the injected /25 appear
# and, after the defence, disappear.
route_protocol() {
    local ctn="$1" dest="$2"
    docker exec "$ctn" sh -c "vtysh -c 'show ip route ${dest} json' 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for pfx,routes in d.items():
    for r in routes:
        if r.get(\"selected\") and pfx==\"${dest}\":
            print(r.get(\"protocol\",\"\")); sys.exit(0)'" 2>/dev/null
}

# ---------------------------------------------------------------------------
# What a router has actually been configured with.
#
# Read through the two commands the handout tells the learner to check their own
# typing with -- `show interface brief` after Part 1's addresses and
# `show running-config` after Part 2's network statements -- rather than through
# `ip addr` on the host side. An oracle key measured by a different route than the
# handout's own is a key that can pass while the handout's instructions do not.

# Every interface on one router that holds an address, as "<ifname> <address/len>"
# per line. One vtysh call per router, not per interface.
configured_addrs() {   # <container>
    docker exec "$1" vtysh -c 'show interface brief' 2>/dev/null \
        | awk 'NR>2 && NF>=4 {print $1, $4}'
}

# The address on one interface, as "<address>/<len>", or nothing if it has none.
configured_addr() {   # <container> <ifname>
    configured_addrs "$1" | awk -v i="$2" '$1==i {print $2; exit}'
}

# How many interfaces across every router hold an address. Zero on a freshly
# spawned lab, twenty-two once Part 1 is done.
addressed_interfaces() {
    local r n=0
    for r in "${ROUTERS[@]}"; do
        n=$(( n + $( configured_addrs "$( router_ctn "$r" )" | grep -c . ) ))
    done
    echo "$n"
}

# The connected prefix zebra derived for one interface, which is how a subnet in
# the addressing plan becomes a value a run can check: the kernel computes it from
# the address and mask the learner typed, not from this file.
connected_prefix_for() {   # <container> <ifname>
    docker exec "$1" sh -c "vtysh -c 'show ip route connected json' 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for pfx,routes in d.items():
    for r in routes:
        for nh in r.get(\"nexthops\",[]):
            if nh.get(\"interfaceName\")==\"$2\": print(pfx); sys.exit(0)'" 2>/dev/null
}

# Does one router hold exactly the addresses this file's plan gives it: one per
# router-to-router link, its leg on its own host subnet, and its loopback? An
# extra address fails as well as a missing one, so a transposed digit cannot pass.
router_addressed_correctly() {   # <router>
    local r="$1" got want peer own rest
    got="$( configured_addrs "$( router_ctn "$r" )" | sort )"
    want="$( { while read -r peer own rest; do
                   [ -z "$peer" ] && continue
                   echo "$( peer_if "$peer" ) ${own}/${LINK_PREFIXLEN}"
               done < <( links_of "$r" )
               echo "${HOST_IF_ROUTER} $( host_gw "$r" )/${HOST_PREFIXLEN}"
               echo "lo $( loopback_ip "$r" )/${LOOPBACK_PREFIXLEN}"; } | sort )"
    [ "$got" = "$want" ] && echo 1 || echo 0
}

all_routers_addressed() {
    local r
    for r in "${ROUTERS[@]}"; do
        [ "$( router_addressed_correctly "$r" )" = "1" ] || { echo 0; return; }
    done
    echo 1
}

# How many `network <prefix> area <area>` lines one router carries.
network_statement_count() {   # <router>
    docker exec "$( router_ctn "$1" )" vtysh -c 'show running-config' 2>/dev/null \
        | grep -cE '^ network [0-9].* area '
}

# The one OSPF area every network statement on every router names. Prints nothing
# unless all five agree, so a lab that drifted into two areas cannot pass a check
# written for one.
configured_ospf_area() {
    local r areas
    areas="$( for r in "${ROUTERS[@]}"; do
                  docker exec "$( router_ctn "$r" )" vtysh -c 'show running-config' 2>/dev/null \
                      | awk '/^ network .* area /{print $NF}'
              done | sort -u | grep -c . )"
    [ "$areas" -eq 1 ] || return 0
    docker exec "$( router_ctn "${ROUTERS[0]}" )" vtysh -c 'show running-config' 2>/dev/null \
        | awk '/^ network .* area /{print $NF; exit}'
}

# The default route a host holds, as the gateway address, read from the `ip route
# show` the handout has the learner run straight after adding it.
host_default_gw() {   # <router whose host to read>
    docker exec "$( host_ctn "$1" )" ip route show default 2>/dev/null \
        | awk '/^default via/ {print $3; exit}'
}

# The metric a router has on a route, read from the same `show ip route <prefix>`
# the handout uses.
route_metric() {   # <container> <prefix>
    docker exec "$1" vtysh -c "show ip route $2" 2>/dev/null \
        | awk -F'metric ' '/metric/ {split($2,a,","); print a[1]; exit}'
}

# The data-plane oracle: who answers on an address, read from a host's curl.
# Prints the banner text, or nothing if the request did not complete.
who_answers() {
    local from_host="$1" ip="$2"
    docker exec "$( host_ctn "$from_host" )" \
        curl -s --max-time 4 "http://${ip}/" 2>/dev/null
}


# OSPF packets arriving on one host's link over a fixed window. A host runs no
# routing protocol, so the only thing that can put an OSPF packet on its link is
# the router at the other end, and the count going to zero is how the lab shows
# that a passive interface has taken effect. Prints a number, always.
hellos_on_host_link() {   # <router whose host to watch> <seconds>
    local n
    n="$( docker exec "$( host_ctn "$1" )" \
            timeout "$2" tcpdump -n -i "$HOST_IF_HOST" -c 20 proto ospf 2>&1 \
          | awk '/packets captured/ {print $1}' )"
    echo "${n:-0}"
}

# Round-trip time in milliseconds between two hosts, as ping's average. Ten
# packets, because one packet on a cold network measures ARP resolution rather
# than the path.
rtt_ms() {
    local from_host="$1" to_ip="$2"
    docker exec "$( host_ctn "$from_host" )" \
        ping -c 10 -i 0.2 -W 2 "$to_ip" 2>/dev/null \
        | awk -F'/' '/^(rtt|round-trip)/ {printf "%.0f\n", $5}'
}

# The routers a packet passes through between two hosts, as a space-separated list
# of router names. Reads traceroute's hop addresses and maps each back to the
# router that owns it, so the answer is names rather than addresses.
path_routers() {
    local from_host="$1" to_ip="$2" line hop out=""
    while read -r hop; do
        for r in "${ROUTERS[@]}"; do
            local peer own rest
            while read -r peer own rest; do
                [ -z "$peer" ] && continue
                if [ "$hop" = "$own" ]; then
                    case " $out " in *" $r "*) ;; *) out="${out:+$out }$r" ;; esac
                fi
            done < <( links_of "$r" )
            if [ "$hop" = "$( host_gw "$r" )" ]; then
                case " $out " in *" $r "*) ;; *) out="${out:+$out }$r" ;; esac
            fi
        done
    done < <( docker exec "$( host_ctn "$from_host" )" \
                traceroute -n -q 1 -w 2 -m 8 "$to_ip" 2>/dev/null \
              | awk 'NR>1 {print $2}' )
    echo "$out"
}
