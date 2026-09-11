#!/usr/bin/env bash
# Draw one range from a seed and write it to state/topology.env.
#
#   scripts/generate.sh <easy|normal|hard> [seed]
#
# Touches no containers and reads nothing that varies outside the seed, so it
# runs in a clean checkout and the seed sweep in selftest.sh costs nothing but
# CPU. That is what makes the generator testable: 25 seeds a tier can be checked
# against every plan invariant without booting anything.
#
# THE SEED DRAWS THE GRAPH BEFORE IT DRAWS ANYTHING ELSE. A range whose shape is
# fixed and whose addresses move is the same exercise twice with different
# digits, so the segment count, the router depth and where the hosts sit are all
# drawn first, and the addressing follows from the plan rather than the other way
# round. Addressing that falls out of the plan stays consistent when the plan
# changes; a plan bolted onto a fixed address scheme does not.
#
# Every draw comes from the single PRNG seeded in lib.sh, in the fixed order
# below. Appending a new attribute at the end keeps old seeds stable; inserting
# one in the middle changes every range, so append rather than insert.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

tier="${1:-}"
seed="${2:-}"

case "$tier" in
    easy|normal|hard) ;;
    *) echo "usage: $( basename "$0" ) <easy|normal|hard> [seed]" >&2; exit 2 ;;
esac

# A seed drawn from /dev/urandom when none was given. This is the ONLY place the
# generator reads anything outside its arguments, and it happens before the PRNG
# is seeded, so the draw sequence itself stays a pure function of (tier, seed).
if [ -z "$seed" ]; then
    seed=$(( 0x$( od -An -N4 -tx1 /dev/urandom | tr -d ' \n' ) ))
fi
case "$seed" in
    ''|*[!0-9]*) echo "seed must be a non-negative integer, got '$seed'" >&2; exit 2 ;;
esac

rng_seed "$seed" "$tier"

# ---------------------------------------------------------------------------
# 1. The graph.

rand_pick ${TIER_SHAPES[$tier]}; shape="$RAND"

# How deep the chain runs on this range. The tier sets a floor and the widest
# shape adds a layer to it, so a learner who draws the biggest network also draws
# the longest way in rather than the same way in across more addresses.
depth="${TIER_DEPTH[$tier]}"
[ "$shape" = mixed ] && depth="$DEPTH_MIXED"

# The mutator, drawn before anything it modifies. It is one word and it changes
# the texture of the whole range rather than its contents, which is what makes it
# the cheapest replayability device here: two ranges with the same shape, the
# same host count and the same services are still two different afternoons when
# one of them answers no echo request and the other has every service on a port
# its registry entry does not name.
#
# `legacy` takes SSH out of the draw and a four-layer chain pivots through an SSH
# host, so the two cannot both hold and the pool is filtered rather than the draw
# being redone. Filtering keeps the draw a single call, which is what keeps the
# sequence a fixed length.
mut_pool=()
for m in "${MUTATORS[@]}"; do
    [ "$depth" -ge 4 ] && [ "$m" = "$MUTATOR_NEEDS_SSH" ] && continue
    mut_pool+=( "$m" )
done
rand_pick "${mut_pool[@]}"; MUTATOR="$RAND"

# The organisation. Nothing about the network depends on it: it decides the zone
# name, the hostnames, the account names, the equipment list and every word of
# prose a learner reads while enumerating.
rand_pick "${ORGS[@]}"; ORG="$RAND"
RANGE_ZONE="${ORG_ZONE[$ORG]}"

seg_min="${TIER_SEG_MIN[$tier]}"; seg_max="${TIER_SEG_MAX[$tier]}"

case "$shape" in
    flat)
        nrouters=1
        # One segment behind the router, and one host on the attacker's own.
        #
        # That local host used to be drawn only at fan and above, which put the
        # tiers the wrong way round: the silent host is the one that listens on
        # nothing and drops echo requests, and on the local segment a single ARP
        # request finds it, while behind a router only a TCP probe against a host
        # that answers with a reset does. Easy was getting the version of that
        # lesson that needs the inference and normal and hard were getting the
        # one command version.
        declare -a router_segcount=( 1 )
        nlocal=1
        ;;
    fan)
        nrouters=1
        rand_range "$(( seg_min > 2 ? seg_min : 2 ))" "$(( seg_max < 3 ? seg_max : 3 ))"
        declare -a router_segcount=( "$RAND" )
        nlocal=1
        ;;
    chain)
        rand_range "$(( seg_min > 2 ? seg_min : 2 ))" "$(( seg_max < 3 ? seg_max : 3 ))"
        nrouters="$RAND"
        declare -a router_segcount=()
        for (( i = 0; i < nrouters; i++ )); do router_segcount+=( 1 ); done
        nlocal=1
        ;;
    mixed)
        # r1 fans to a segment and to r2, which fans to two more.
        nrouters=2
        declare -a router_segcount=( 1 2 )
        nlocal=1
        ;;
esac

ROUTERS=()
for (( i = 1; i <= nrouters; i++ )); do ROUTERS+=( "r$i" ); done

# The router tree. r1 hangs off the attacker's own segment and has no parent;
# every other router hangs off the one before it, which is what makes `chain` a
# line and `mixed` a line with a wider leaf.
declare -A ROUTER_PARENT=()
for (( i = 2; i <= nrouters; i++ )); do ROUTER_PARENT["r$i"]="r$(( i - 1 ))"; done

nseg=0
for c in "${router_segcount[@]}"; do nseg=$(( nseg + c )); done

rand_range "${TIER_DEAD_MIN[$tier]}" "${TIER_DEAD_MAX[$tier]}"; ndead="$RAND"

# `segmented` adds one more routed-and-empty subnet, and one of them answers an
# administrative rejection rather than a host unreachable. The two answers mean
# different things and a learner who reads them as the same thing sweeps an empty
# block twice: a host unreachable says the router tried and nothing was there, an
# administratively-prohibited says the router did not try.
[ "$MUTATOR" = segmented ] && ndead=$(( ndead + 1 ))

# ---------------------------------------------------------------------------
# 2. The addressing, derived from the plan above.
#
# Every range lives inside one /16 of the AS's own /8, and the attacker's
# interface is in the .0 of it. That second octet is the handle the hard tier
# turns on: the learner is told nothing, reads their own address, and the /16 to
# search falls out of it.

rand_range 1 254; second="$RAND"
RANGE_PREFIX="${AS}.${second}.0.0/16"
ATT_SUBNET="${AS}.${second}.0.0/24"
ATT_GW="${AS}.${second}.0.1"
rand_range 10 90; ATTACKER_IP="${AS}.${second}.0.${RAND}"

# Third octets for every subnet past the attacker's own. Drawn distinct and
# pairwise non-consecutive so that a learner cannot read the rest of the map off
# the two subnets they have already found. 0 is the attacker's own, so the pool
# starts at 2 and every drawn value stays at least 2 from every other.
declare -a thirds=()
THIRD=0
draw_third() {   # -> $THIRD
    local v ok c
    while :; do
        rand_range 2 250; v="$RAND"
        ok=1
        for c in "${thirds[@]}"; do
            [ "$(( v > c ? v - c : c - v ))" -lt 2 ] && { ok=0; break; }
        done
        [ "$ok" -eq 1 ] && { thirds+=( "$v" ); THIRD="$v"; return; }
    done
}

# Segments, in router order: the attacker's own first, then each router's.
SEGMENTS=( seg0 )
declare -A SEG_SUBNET=( [seg0]="$ATT_SUBNET" )
declare -A SEG_BRIDGE=( [seg0]="br0" )
declare -A SEG_ROUTER=( [seg0]="r1" )
declare -A SEG_GW=(     [seg0]="$ATT_GW" )
declare -A SEG_HOPS=(   [seg0]=0 )

bridge_n=1
segn=0
for (( i = 0; i < nrouters; i++ )); do
    r="${ROUTERS[$i]}"
    for (( c = 0; c < router_segcount[i]; c++ )); do
        segn=$(( segn + 1 ))
        draw_third; t="$THIRD"
        s="seg${segn}"
        SEGMENTS+=( "$s" )
        SEG_SUBNET["$s"]="${AS}.${second}.${t}.0/24"
        SEG_BRIDGE["$s"]="br${bridge_n}"; bridge_n=$(( bridge_n + 1 ))
        SEG_ROUTER["$s"]="$r"
        SEG_GW["$s"]="${AS}.${second}.${t}.1"
        SEG_HOPS["$s"]=$(( i + 1 ))
    done
done

# Dead ranges: a subnet that appears in a router's table and holds no host.
# Sweeping one buys nothing and costs real time, so reading an ICMP unreachable
# rather than waiting out a full sweep is the skill it drills. Each one is wired
# exactly like a live segment, bridge and router interface and all; the only
# difference is that no host is plugged into it.
DEAD_RANGES=()
declare -A DEAD_SUBNET=() DEAD_BRIDGE=() DEAD_ROUTER=() DEAD_GW=() DEAD_ANSWER=()
for (( d = 1; d <= ndead; d++ )); do
    draw_third; t="$THIRD"
    n="dead${d}"
    rand "$nrouters"; r="${ROUTERS[$RAND]}"
    DEAD_RANGES+=( "$n" )
    DEAD_SUBNET["$n"]="${AS}.${second}.${t}.0/24"
    DEAD_BRIDGE["$n"]="br${bridge_n}"; bridge_n=$(( bridge_n + 1 ))
    DEAD_ROUTER["$n"]="$r"
    DEAD_GW["$n"]="${AS}.${second}.${t}.1"
    DEAD_ANSWER["$n"]="unreachable"
done
# One of them answers an administrative rejection instead, on a segmented range.
if [ "$MUTATOR" = segmented ] && [ "${#DEAD_RANGES[@]}" -gt 0 ]; then
    rand "${#DEAD_RANGES[@]}"; DEAD_ANSWER["${DEAD_RANGES[$RAND]}"]="prohibited"
fi

# The vault segment, on ranges three layers deep and more. One bridge, one router
# interface and one container, behind the router furthest from the attacker.
#
# It is drawn from the same third-octet pool as everything else, so it obeys the
# same non-consecutive rule and cannot collide with a segment or a dead range. It
# is NOT a live segment and NOT a dead range: the scoring never sees it, in
# either direction, which is what lets the filter in front of it answer a probe
# honestly with an ICMP administratively-prohibited. That answer is a breadcrumb
# saying a door exists, and because the subnet behind it is unscored, following
# it up cannot cost a learner marks.
VAULT_NET=""; VAULT_BRIDGE=""; VAULT_ROUTER=""; VAULT_GW=""; VAULT_IP=""
if [ "$depth" -ge 3 ]; then
    draw_third; t="$THIRD"
    VAULT_NET="${AS}.${second}.${t}.0/24"
    VAULT_BRIDGE="br${bridge_n}"; bridge_n=$(( bridge_n + 1 ))
    VAULT_ROUTER="${ROUTERS[$(( nrouters - 1 ))]}"
    VAULT_GW="${AS}.${second}.${t}.1"
    # Off .1, off the round numbers, and drawn rather than fixed, so the address
    # is not something a learner can write down once and reuse next spawn.
    rand_range 20 240; vo="$RAND"
    case "$vo" in 100|200) vo=$(( vo + 7 )) ;; esac
    VAULT_IP="${AS}.${second}.${t}.${vo}"
fi

# Router-to-router links: point-to-point veths, the same primitive the attacker's
# own link would be, so depth costs one container per router and no bridge. Both
# ends are router interfaces, and both are found by traceroute rather than by a
# sweep, which is what makes depth worth scoring separately from reach.
TRANSITS=()
declare -A TRANSIT_SUBNET=() TRANSIT_A=() TRANSIT_B=() TRANSIT_A_IP=() TRANSIT_B_IP=()
for (( i = 2; i <= nrouters; i++ )); do
    draw_third; t="$THIRD"
    n="t$(( i - 1 ))"
    TRANSITS+=( "$n" )
    TRANSIT_SUBNET["$n"]="${AS}.${second}.${t}.0/30"
    TRANSIT_A["$n"]="r$(( i - 1 ))"
    TRANSIT_B["$n"]="r${i}"
    TRANSIT_A_IP["$n"]="${AS}.${second}.${t}.1"
    TRANSIT_B_IP["$n"]="${AS}.${second}.${t}.2"
done

# ---------------------------------------------------------------------------
# 3. Where the hosts sit.
#
# Uneven fan-out is drawn, not averaged: one bridge with a single host and
# another with five is the case a learner who assumes the segments are the same
# size scans the wrong one hard. Every live segment gets one host, and every host
# past that is dropped on a segment drawn afresh.

rand_range "${TIER_HOST_MIN[$tier]}" "${TIER_HOST_MAX[$tier]}"; nhosts="$RAND"
[ "$nhosts" -gt "$MAX_HOSTS" ] && nhosts="$MAX_HOSTS"

declare -A seg_count=()
for s in "${SEGMENTS[@]}"; do seg_count["$s"]=0; done

# The host on the attacker's own segment, at every shape but flat. It is the only
# way to show the distinction a flat range cannot: on the local segment an ARP
# request finds a host that drops echo requests and listens on nothing, and
# behind a router nothing does.
[ "$nlocal" -gt 0 ] && seg_count[seg0]="$nlocal"

remaining=$(( nhosts - nlocal ))
routed_segs=( "${SEGMENTS[@]:1}" )
for s in "${routed_segs[@]}"; do
    seg_count["$s"]=1
    remaining=$(( remaining - 1 ))
done
# The guard is not decoration. The loop redraws when the segment it picked is
# already full, so a draw where every routed segment is at the cap and hosts are
# still unplaced spins forever rather than failing. That cannot happen at the
# sizes the tier table sets, and it is exactly the kind of thing a later change
# to TIER_HOST_MAX would make happen silently.
seg_cap=7
spins=0
while [ "$remaining" -gt 0 ]; do
    spins=$(( spins + 1 ))
    if [ "$spins" -gt 10000 ]; then
        echo "cannot place $remaining host(s): every segment is at the cap of $seg_cap" >&2
        exit 1
    fi
    rand "${#routed_segs[@]}"; s="${routed_segs[$RAND]}"
    [ "${seg_count[$s]}" -ge "$seg_cap" ] && continue
    seg_count["$s"]=$(( seg_count[$s] + 1 ))
    remaining=$(( remaining - 1 ))
done

# Addresses inside each segment. The rules below are what stop a learner reading
# the answer off the shape rather than off a scan: nothing on .1 (the gateway),
# nothing on .100, .200 or .254, no two hosts on consecutive addresses, and a
# segment holding more than one host is not packed into its low end.
HOSTS=()
declare -A TARGET_IP=() TARGET_SEG=()
declare -A SEG_HOSTS=()
for s in "${SEGMENTS[@]}"; do SEG_HOSTS["$s"]=""; done

hostn=0
for s in "${SEGMENTS[@]}"; do
    want="${seg_count[$s]}"
    [ "$want" -eq 0 ] && continue
    base="${SEG_SUBNET[$s]%.0/24}"
    declare -a octets=()
    # On the attacker's own segment the attacker's address is seeded into the
    # list before anything is drawn, so the rules below keep every host clear of
    # it as well as of each other. Without this a host could be drawn onto the
    # address the attacker itself holds, and the range would not boot.
    skip=0
    if [ "$s" = "seg0" ]; then
        octets+=( "${ATTACKER_IP##*.}" )
        skip=1
        want=$(( want + 1 ))
    fi
    while [ "${#octets[@]}" -lt "$want" ]; do
        rand_range 2 253; o="$RAND"
        case "$o" in 100|200) continue ;; esac
        ok=1
        for c in "${octets[@]}"; do
            [ "$(( o > c ? o - c : c - o ))" -lt 2 ] && { ok=0; break; }
        done
        [ "$ok" -eq 0 ] && continue
        octets+=( "$o" )
        # Not packed into the low end: once the last slot is being filled and
        # every address so far is below .129, that slot is redrawn until it is
        # not. Redrawing consumes the PRNG in a fixed order, so this stays
        # reproducible.
        if [ "${#octets[@]}" -eq "$want" ] && [ "$want" -ge 2 ]; then
            high=0
            for c in "${octets[@]}"; do [ "$c" -gt 128 ] && high=1; done
            [ "$high" -eq 0 ] && unset 'octets[${#octets[@]}-1]' && octets=( "${octets[@]}" )
        fi
    done
    for o in "${octets[@]:$skip}"; do
        hostn=$(( hostn + 1 ))
        h="host${hostn}"
        HOSTS+=( "$h" )
        TARGET_IP["$h"]="${base}.${o}"
        TARGET_SEG["$h"]="$s"
        SEG_HOSTS["$s"]="${SEG_HOSTS[$s]:+${SEG_HOSTS[$s]} }$h"
    done
    unset octets
done

# ---------------------------------------------------------------------------
# 4. What each host is, and what it runs.
#
# The class comes before the service and the way in comes before both. A host's
# CLASS decides which services it may run, because a power distribution unit does
# not run a file-sync daemon and a range where it might would teach that a
# fingerprint is guesswork. The UNLOCK PLAN decides which services the range must
# hold, because the chain runs on assets and each asset has a set of services
# that can yield it.

# 4a. The way in, planned before anything is placed.
#
# The chain needs the name of the shared account, its password, and on a
# three-layer range the passphrase on the key that opens the vault. Each of those
# is an asset, each asset has producers in lib.sh, and each producer is an action
# against one service. Drawing the producers is what decides which services this
# range has to hold, and the tier's redundancy dial says how many are drawn
# beyond the one the chain needs. That is what turns the way in from a corridor
# into a graph: at hard there are three ways to learn the account name and two
# ways to learn its password, and which one a learner finds first is theirs.

PICKED=()
pick_n() {   # pick_n <count> <item...> -> $PICKED, in drawn order
    local want="$1"; shift
    local pool=( "$@" )
    rand_shuffle pool
    PICKED=( "${pool[@]:0:$want}" )
}

K="${TIER_REDUNDANCY[$tier]}"

pick_n $(( 1 + K )) ${ASSET_PRODUCERS[account]}
account_unlocks=( "${PICKED[@]}" )

# The dictionary attack against the telnet login is always one of the routes to
# the password, because the foothold is a telnet login on every range. The others
# are drawn, and one of them needs a filename before it yields anything, so a
# range that draws it draws something that names the file as well.
password_unlocks=( weak-telnet-pass )
filename_unlocks=()
if [ "$K" -gt 0 ]; then
    pick_n "$K" tftp-file redis-open
    password_unlocks+=( "${PICKED[@]}" )
fi
case " ${password_unlocks[*]} " in
    *" tftp-file "*)
        pick_n 1 ${ASSET_PRODUCERS[filename]}
        filename_unlocks=( "${PICKED[@]}" )
        ;;
esac

passphrase_unlocks=()
if [ "$depth" -ge 3 ]; then
    pick_n $(( 1 + K )) ${ASSET_PRODUCERS[passphrase]}
    passphrase_unlocks=( "${PICKED[@]}" )
fi

# One service holds one secret, so a producer drawn for two assets keeps the one
# the chain depends on and gives up the other. The passphrase is what the vault
# turns on, so it wins; anything it displaces was a redundant route to something
# the range can still reach another way.
if [ "${#passphrase_unlocks[@]}" -gt 0 ]; then
    keep=()
    for u in "${password_unlocks[@]}"; do
        case " ${passphrase_unlocks[*]} " in *" $u "*) continue ;; esac
        keep+=( "$u" )
    done
    password_unlocks=( "${keep[@]}" )
    keep=()
    for u in ${filename_unlocks[@]+"${filename_unlocks[@]}"}; do
        case " ${passphrase_unlocks[*]} " in *" $u "*) continue ;; esac
        keep+=( "$u" )
    done
    filename_unlocks=( ${keep[@]+"${keep[@]}"} )
fi
# A TFTP route whose filename producer was just taken away is a file nobody on
# the range can name, so the route goes with it.
case " ${password_unlocks[*]} " in
    *" tftp-file "*)
        if [ "${#filename_unlocks[@]}" -eq 0 ]; then
            keep=()
            for u in "${password_unlocks[@]}"; do [ "$u" = tftp-file ] || keep+=( "$u" ); done
            password_unlocks=( "${keep[@]}" )
        fi
        ;;
esac

# The first producer of every asset is the one the chain needs and is never
# dropped; the extras are redundancy and come off the end when the range does not
# have the hosts to carry them. The filename producer is listed BEFORE the unlock
# that needs it, so trimming from the end takes the dependent away first and
# never leaves an unlock whose requirement was trimmed out from under it.
req_unlocks=( "${account_unlocks[0]}" weak-telnet-pass )
[ "$depth" -ge 3 ] && req_unlocks+=( "${passphrase_unlocks[0]}" )

opt_unlocks=()
for (( i = 1; i < ${#account_unlocks[@]}; i++ )); do opt_unlocks+=( "${account_unlocks[$i]}" ); done
for (( i = 1; i < ${#passphrase_unlocks[@]}; i++ )); do opt_unlocks+=( "${passphrase_unlocks[$i]}" ); done
for (( i = 1; i < ${#password_unlocks[@]}; i++ )); do
    u="${password_unlocks[$i]}"
    if [ "$u" = tftp-file ] && [ "${#filename_unlocks[@]}" -gt 0 ]; then
        opt_unlocks+=( "${filename_unlocks[0]}" )
    fi
    opt_unlocks+=( "$u" )
done

# The host on the attacker's own segment runs nothing at all, so it is not a
# candidate for anything the plan places.
local_host=""
[ "$nlocal" -gt 0 ] && local_host="${SEG_HOSTS[seg0]%% *}"
service_hosts=()
for h in "${HOSTS[@]}"; do [ "$h" = "$local_host" ] || service_hosts+=( "$h" ); done

forced=()
add_forced() { case " ${forced[*]} " in *" $1 "*) ;; *) forced+=( "$1" ) ;; esac; }

# One free draw is held back, so that no range is entirely made of machines the
# plan asked for. A range where every service is load-bearing reads as a puzzle
# rather than as a network.
max_forced=$(( ${#service_hosts[@]} - 1 ))
[ "$max_forced" -lt 1 ] && max_forced=1
while :; do
    forced=()
    add_forced telnet                    # the foothold is a login, at every tier
    for u in "${req_unlocks[@]}"; do add_forced "${UNLOCK_PROFILE[$u]}"; done
    for u in ${opt_unlocks[@]+"${opt_unlocks[@]}"}; do add_forced "${UNLOCK_PROFILE[$u]}"; done
    # The zone transfer is the range's one shortcut to the whole map, and it is
    # deliberately not on the easy tier, where the map is handed over anyway.
    [ "$tier" != easy ] && add_forced dns
    # A four-layer range pivots through a host whose SSH the foothold's key
    # opens, so that host has to be running SSH in the first place.
    [ "$depth" -ge 4 ] && add_forced ssh
    [ "${#forced[@]}" -le "$max_forced" ] && break
    [ "${#opt_unlocks[@]}" -gt 0 ] || break
    unset 'opt_unlocks[${#opt_unlocks[@]}-1]'
    opt_unlocks=( ${opt_unlocks[@]+"${opt_unlocks[@]}"} )
done
# Deduplicated: a producer drawn for two assets is still one action against one
# service, and writing its parameters twice would put the same key=value pair in
# the host's parameter list twice.
unlocks=()
for u in "${req_unlocks[@]}" ${opt_unlocks[@]+"${opt_unlocks[@]}"}; do
    case " ${unlocks[*]:-} " in *" $u "*) continue ;; esac
    unlocks+=( "$u" )
done

# 4b. Which host is which, and what each one runs.
#
# A forced profile is placed first and the machine's class follows from it: a
# class is evidence precisely because the service mix is not uniform across the
# four, so a host running a print protocol is an appliance and not a server. On
# every host the plan did not ask for, the draw runs the other way round, class
# first and then a service that class would plausibly run.

declare -A TARGET_PROFILE=() TARGET_CLASS=()

class_for_profile() {   # -> $RAND, a class that may run <profile>
    local p="$1" c cands=()
    for c in "${CLASSES[@]}"; do
        case " ${CLASS_PROFILES[$c]} " in *" $p "*) cands+=( "$c" ) ;; esac
    done
    [ "${#cands[@]}" -gt 0 ] || cands=( server )
    rand_pick "${cands[@]}"
}

pool=( "${service_hosts[@]}" )
rand_shuffle pool
idx=0
for p in "${forced[@]}"; do
    [ "$idx" -lt "${#pool[@]}" ] || break
    h="${pool[$idx]}"; idx=$(( idx + 1 ))
    TARGET_PROFILE["$h"]="$p"
    class_for_profile "$p"; TARGET_CLASS["$h"]="$RAND"
done

# The draw pool for everything else. `legacy` takes SSH out of it and weights the
# cleartext estate up, which is what a network that never finished a migration
# looks like from a scanner.
draw_pool=()
for p in "${PROFILE_POOL[@]}"; do
    [ "$MUTATOR" = legacy ] && [ "$p" = ssh ] && continue
    draw_pool+=( "$p" )
done
[ "$MUTATOR" = legacy ] && draw_pool+=( telnet telnet telnet ftp ftp tftp tftp syslog )

for (( ; idx < ${#pool[@]}; idx++ )); do
    h="${pool[$idx]}"
    rand_pick "${CLASSES[@]}"; c="$RAND"
    cands=()
    for p in "${draw_pool[@]}"; do
        [ "$p" = none ] && continue
        case " ${CLASS_PROFILES[$c]} " in *" $p "*) cands+=( "$p" ) ;; esac
    done
    [ "${#cands[@]}" -gt 0 ] || cands=( http )
    rand_pick "${cands[@]}"
    TARGET_PROFILE["$h"]="$RAND"
    TARGET_CLASS["$h"]="$c"
done

# Exactly one host runs nothing at all, and where the shape gives the attacker a
# segment of its own it is the host on that segment: an ARP request finds it, an
# echo request does not, and a port scan reports nothing open. A machine with an
# address and no service is a workstation, which is also the only class whose
# service list allows one.
if [ -n "$local_host" ]; then
    no_service_host="$local_host"
else
    spare=( "${pool[@]:${#forced[@]}}" )
    [ "${#spare[@]}" -gt 0 ] || spare=( "${pool[${#pool[@]}-1]}" )
    rand "${#spare[@]}"; no_service_host="${spare[$RAND]}"
fi
TARGET_PROFILE["$no_service_host"]="none"
TARGET_CLASS["$no_service_host"]="workstation"

# 4c. The implementation behind each service class that has two.
#
# The chain's SSH pivot is pinned to OpenSSH rather than drawn. Dropbear reads
# the same authorized_keys file and would serve a learner identically, but
# solve.sh has to drive that hop non-interactively on every seed, and pinning one
# implementation there is cheaper than proving two of them behave the same under
# a harness.
declare -A TARGET_IMPL=()
for h in "${HOSTS[@]}"; do
    p="${TARGET_PROFILE[$h]}"
    if [ -n "${PROFILE_IMPLS[$p]:-}" ]; then
        rand_pick ${PROFILE_IMPLS[$p]}; TARGET_IMPL["$h"]="$RAND"
    else
        TARGET_IMPL["$h"]=""
    fi
done

# 4d. Hostnames.
#
# A hostname is inside the bytes nmap's version detection reads back and it is
# what a reverse lookup returns, so it is pinned here rather than left to the
# container name. It is built from the organisation's prefix and the class's own
# vocabulary, so an estate reads as one organisation's rather than as nine
# unrelated machines, and the name itself is one of the four weak signals a class
# is inferred from.
declare -A TARGET_HOSTNAME=()
used_names=" "
for h in "${HOSTS[@]}"; do
    c="${TARGET_CLASS[$h]}"
    while :; do
        rand_pick ${CLASS_HOSTPART[$c]}; part="$RAND"
        rand_range 1 9; name="${ORG_PREFIX[$ORG]}-${part}${RAND}"
        case "$used_names" in *" $name "*) continue ;; esac
        break
    done
    used_names="${used_names}${name} "
    TARGET_HOSTNAME["$h"]="$name"
done

# 4e. The ports, and every service each host runs.
#
# TARGET_SERVICES is the authority and TARGET_PORTS is derived from it. A host
# runs one primary service and may run more: the `chatty` mutator adds an SNMP
# agent to most machines and `noisy` adds junk listeners, and spawn.sh runs one
# profile script per entry with only that entry's ports in its environment.
#
# A service is on the port its registry entry names unless the seed moved it,
# which is what gives version detection something to be right about: a learner
# who reads a service off its port number is wrong about a third of this range.
# The profiles with no alternates in lib.sh are never moved.

SPECS=""
draw_ports() {   # draw_ports <profile> -> $SPECS, comma separated
    local p="$1" port proto alts alt
    SPECS=""
    [ "$p" = none ] && return
    alts="${PROFILE_ALT_PORTS[$p]:-}"
    if [ -n "$alts" ] && { [ "$MUTATOR" = relocated ] || rand_chance 1 3; }; then
        rand_pick $alts; port="$RAND"
    else
        port="${PROFILE_PORT[$p]}"
    fi
    for proto in ${PROFILE_PROTO[$p]}; do
        SPECS="${SPECS:+$SPECS,}${proto}/${port}"
    done
    # A second web listener, on a third of web hosts. Two ports, one piece of
    # software, one version: the case where a port list and a service list are
    # not the same length.
    if [ "$p" = http ] && rand_chance 1 3; then
        rand_pick $alts; alt="$RAND"
        [ "$alt" != "$port" ] && SPECS="${SPECS},tcp/${alt}"
    fi
    # The explicit success is load-bearing under `set -e`. The test above is
    # false whenever the second listener drew the port the first one already
    # holds, that test is the function's last statement, so the function returns
    # non-zero, and the caller is a simple command that then kills the generator
    # on a range with nothing wrong with it. Any predicate-shaped statement at
    # the end of a function here needs the same line.
    return 0
}

declare -A TARGET_SERVICES=() TARGET_PORTS=()
for h in "${HOSTS[@]}"; do
    draw_ports "${TARGET_PROFILE[$h]}"
    TARGET_SERVICES["$h"]="${TARGET_PROFILE[$h]}:${SPECS}"
done

# `chatty`: an SNMP agent on most machines, so the interface tables become a
# second route to the map and UDP enumeration is the primary work rather than an
# afterthought.
if [ "$MUTATOR" = chatty ]; then
    for h in "${HOSTS[@]}"; do
        [ "$h" = "$no_service_host" ] && continue
        [ "${TARGET_PROFILE[$h]}" = snmp ] && continue
        rand_chance 3 4 || continue
        TARGET_SERVICES["$h"]="${TARGET_SERVICES[$h]} snmp:udp/${PROFILE_PORT[snmp]}"
    done
fi

# `noisy`: six to eight listeners with nothing behind them, on three machines.
if [ "$MUTATOR" = noisy ]; then
    cand=()
    for h in "${HOSTS[@]}"; do [ "$h" = "$no_service_host" ] || cand+=( "$h" ); done
    rand_shuffle cand
    nnoisy=3; [ "${#cand[@]}" -lt 3 ] && nnoisy="${#cand[@]}"
    for (( i = 0; i < nnoisy; i++ )); do
        h="${cand[$i]}"
        rand_range "$JUNK_MIN" "$JUNK_MAX"; want="$RAND"
        jp=( "${JUNK_PORTS[@]}" ); rand_shuffle jp
        # The host's own ports are skipped rather than redrawn, so a junk
        # listener never lands on a port a real service already holds.
        taken=" "
        for entry in ${TARGET_SERVICES[$h]}; do
            espec="${entry#*:}"
            for s in ${espec//,/ }; do taken="${taken}${s} "; done
        done
        specs=""; got=0
        for (( j = 0; j < ${#jp[@]} && got < want; j++ )); do
            case "$taken" in *" tcp/${jp[$j]} "*) continue ;; esac
            specs="${specs:+$specs,}tcp/${jp[$j]}"; got=$(( got + 1 ))
        done
        [ -n "$specs" ] && TARGET_SERVICES["$h"]="${TARGET_SERVICES[$h]} junk:${specs}"
    done
fi

# The union, which is what the packet filter and the harness read.
for h in "${HOSTS[@]}"; do
    ports=""
    for entry in ${TARGET_SERVICES[$h]}; do
        specs="${entry#*:}"
        [ -n "$specs" ] || continue
        for s in ${specs//,/ }; do ports="${ports:+$ports }$s"; done
    done
    TARGET_PORTS["$h"]="$ports"
done

# ---------------------------------------------------------------------------
# 5. How each host behaves: ICMP, and what a port with nothing behind it does.
#
# A host that drops echo requests always answers a shut port with a reset, so a
# TCP probe to any port on it establishes that it is running. Without that rule a
# host could draw silence on both and be findable only by a full 65535-port
# sweep, which is not a discovery lesson, it is a waiting game.
declare -A TARGET_ICMP=() TARGET_SHUT=() TARGET_FILTERED=()
for h in "${HOSTS[@]}"; do
    if rand_chance 1 4; then
        TARGET_ICMP["$h"]="drop"; TARGET_SHUT["$h"]="reject"
    else
        TARGET_ICMP["$h"]="reply"
        if rand_chance 1 3; then TARGET_SHUT["$h"]="drop"; else TARGET_SHUT["$h"]="reject"; fi
    fi
done

case "$MUTATOR" in
    quiet)
        # Most of the estate stops answering echo requests, which is what a
        # network with a host-based firewall standard looks like. Every one of
        # them still refuses a shut port, so a TCP probe finds what a ping sweep
        # missed and the lesson is that the sweep was the wrong question.
        for h in "${HOSTS[@]}"; do
            rand_chance 3 4 || continue
            TARGET_ICMP["$h"]="drop"; TARGET_SHUT["$h"]="reject"
        done
        ;;
    locked-down)
        # Shut ports are dropped rather than refused nearly everywhere, so a scan
        # reports `filtered` where it used to report `closed` and a learner has
        # to read the distinction honestly. The hosts that drop echo requests are
        # left refusing, because a host that drops both is a host nothing short
        # of a full sweep finds.
        for h in "${HOSTS[@]}"; do
            [ "${TARGET_ICMP[$h]}" = drop ] && continue
            TARGET_SHUT["$h"]="drop"
        done
        ;;
esac

# A service that never sends a byte is only honest on a host that refuses its
# shut ports. On a host that drops them every port reads `open|filtered` alike
# and the comparison the lesson turns on is gone.
for h in "${HOSTS[@]}"; do
    for entry in ${TARGET_SERVICES[$h]}; do
        [ "${entry%%:*}" = "$PROFILE_SILENT" ] && TARGET_SHUT["$h"]="reject"
    done
done

# The silent local host drops echo requests and listens on nothing, so on the
# local segment it is found by an ARP request and by nothing else.
[ -n "$local_host" ] && { TARGET_ICMP["$local_host"]="drop"; TARGET_SHUT["$local_host"]="reject"; }

# At least one host that a ping sweep misses and a TCP probe finds. Every range
# turns on that disagreement, so if the draw above produced none, the first
# service host behind a router is made silent.
silent_ok=0
for h in "${HOSTS[@]}"; do
    [ "${TARGET_ICMP[$h]}" = "drop" ] && [ -n "${TARGET_PORTS[$h]}" ] && silent_ok=1
done
if [ "$silent_ok" -eq 0 ]; then
    for h in "${HOSTS[@]}"; do
        if [ -n "${TARGET_PORTS[$h]}" ] && [ "${TARGET_SEG[$h]}" != "seg0" ]; then
            TARGET_ICMP["$h"]="drop"; TARGET_SHUT["$h"]="reject"; break
        fi
    done
fi

# Per-port state, on a host that refuses its shut ports. A handful of named ports
# are dropped instead, so one machine reports open, closed and filtered at once,
# which is the state table the field manual teaches and which a per-host setting
# could never produce.
for h in "${HOSTS[@]}"; do
    TARGET_FILTERED["$h"]=""
    [ "${TARGET_SHUT[$h]}" = reject ] || continue
    rand_chance 1 2 || continue
    fc=( "${FILTER_CANDIDATES[@]}" ); rand_shuffle fc
    rand_range 1 3; want="$RAND"
    got=""; n=0
    for (( i = 0; i < ${#fc[@]} && n < want; i++ )); do
        case " ${TARGET_PORTS[$h]} " in *" tcp/${fc[$i]} "*) continue ;; esac
        got="${got:+$got }tcp/${fc[$i]}"; n=$(( n + 1 ))
    done
    TARGET_FILTERED["$h"]="$got"
done

# ---------------------------------------------------------------------------
# 6. The unlocks, placed on the machines that run their services.
#
# Section 4a drew WHICH producers this range carries. This puts each one on a
# host running the service it acts against, and writes the parameter its profile
# script reads. The intel token a learner submits for it is the unlock's own
# name, which is why the vocabulary in lib.sh is the list of unlock ids.

rand_pick ${ORG_ACCOUNTS[$ORG]}; RANGE_LEAK_ACCOUNT="$RAND"

# The operations account's password, taken from the wordlist baked into the
# image. It is drawn from the back half of the list on purpose, so that a learner
# watches hydra work through it rather than hitting the answer first try. The
# list is read from the lab's own image/ directory, which is a file in the
# checkout and not a container, so the draw stays a pure function of the seed.
pass_file="$LAB_DIR/image/passwords.txt"
pass_count="$( wc -l < "$pass_file" )"
rand_range "$(( pass_count / 4 ))" "$(( pass_count - 1 ))"; pass_idx="$RAND"
RANGE_WEAK_PASS="$( sed -n "$(( pass_idx + 1 ))p" "$pass_file" )"

# The passphrase on the vault's key. Words rather than the hex a token uses,
# because a learner reads this one out of a file and types it into ssh-add, and
# deliberately not from the range's password list: this one is found, not
# cracked, and putting it on a wordlist would make hydra a shortcut past the
# branch it exists to force.
CHAIN_PASSPHRASE=""
if [ "$depth" -ge 3 ]; then
    rand_pick "${PASSPHRASE_WORDS[@]}"; p1="$RAND"
    rand_pick "${PASSPHRASE_WORDS[@]}"; p2="$RAND"
    rand_pick "${PASSPHRASE_WORDS[@]}"; p3="$RAND"
    rand_range 10 99; pn="$RAND"
    CHAIN_PASSPHRASE="${p1}-${p2}-${p3}-${pn}"
fi

# The name of the file the TFTP route turns on. TFTP has no listing, so the name
# is the whole of the secret, and it follows the organisation's own naming
# standard because that is what makes it guessable-looking and not guessable.
site_lower="$( echo "${ORG_SITES[$ORG]%% *}" | tr 'A-Z' 'a-z' | tr -d ' ' )"
rand_pick running-config startup-config backup archive; RANGE_TFTP_FILE="${ORG_PREFIX[$ORG]}-${site_lower}-${RAND}.cfg"

declare -A TARGET_INTEL=() TARGET_PARAM=()
for h in "${HOSTS[@]}"; do TARGET_INTEL["$h"]=""; TARGET_PARAM["$h"]=""; done

add_intel() {
    case " ${TARGET_INTEL[$1]} " in *" $2 "*) return ;; esac
    TARGET_INTEL["$1"]="${TARGET_INTEL[$1]:+${TARGET_INTEL[$1]} }$2"
}
add_param() { TARGET_PARAM["$1"]="${TARGET_PARAM[$1]:+${TARGET_PARAM[$1]} }$2"; }

by_profile() {   # by_profile <profile> -> host tokens, in host order
    local p="$1" h entry out=""
    for h in "${HOSTS[@]}"; do
        for entry in ${TARGET_SERVICES[$h]}; do
            [ "${entry%%:*}" = "$p" ] && out="${out:+$out }$h"
        done
    done
    echo "$out"
}

host_running() {   # host_running <profile> -> $RAND, a host token or empty
    local cands=( $( by_profile "$1" ) )
    if [ "${#cands[@]}" -eq 0 ]; then RAND=""; return; fi
    rand "${#cands[@]}"; RAND="${cands[$RAND]}"
}

# Which host each unlock was placed on, so the chain and the solver can find the
# one that carries the passphrase without searching for it.
declare -A UNLOCK_HOST=()
anon_ftp=""
placed_unlocks=()

for u in "${unlocks[@]}"; do
    host_running "${UNLOCK_PROFILE[$u]}"; uh="$RAND"
    [ -n "$uh" ] || continue
    UNLOCK_HOST["$u"]="$uh"
    placed_unlocks+=( "$u" )
    case "$u" in
        leaked-account)
            add_param "$uh" "ftp_anon=yes"
            add_param "$uh" "leak_account=${RANGE_LEAK_ACCOUNT}"
            add_intel "$uh" anon-ftp
            add_intel "$uh" leaked-account
            anon_ftp="$uh"
            ;;
        leaked-passphrase)
            add_param "$uh" "ftp_anon=yes"
            add_param "$uh" "key_passphrase=${CHAIN_PASSPHRASE}"
            add_intel "$uh" anon-ftp
            add_intel "$uh" leaked-passphrase
            anon_ftp="$uh"
            ;;
        smtp-vrfy)
            add_param "$uh" "smtp_account=${RANGE_LEAK_ACCOUNT}"
            add_intel "$uh" smtp-vrfy
            ;;
        snmp-public)
            add_param "$uh" "leak_account=${RANGE_LEAK_ACCOUNT}"
            add_intel "$uh" snmp-public
            ;;
        hidden-path)
            rand_pick "${HIDDEN_PATHS[@]}"
            add_param "$uh" "hidden_path=$RAND"
            add_param "$uh" "leak_account=${RANGE_LEAK_ACCOUNT}"
            add_intel "$uh" hidden-path
            ;;
        weak-telnet-pass)
            add_param "$uh" "ops_account=${RANGE_LEAK_ACCOUNT}:${RANGE_WEAK_PASS}"
            add_intel "$uh" weak-telnet-pass
            ;;
        tftp-file)
            add_param "$uh" "tftp_file=${RANGE_TFTP_FILE}"
            add_param "$uh" "tftp_account=${RANGE_LEAK_ACCOUNT}"
            add_param "$uh" "tftp_password=${RANGE_WEAK_PASS}"
            add_intel "$uh" tftp-file
            ;;
        redis-open|rsync-module|mqtt-open)
            # One store, one secret. Which secret it holds depends on which asset
            # this producer was drawn for: a passphrase where the range has a
            # vault, the shared account's password where it is a second route to
            # the login, and the TFTP filename where it is what unlocks that.
            kind=password; secret="$RANGE_WEAK_PASS"
            case " ${filename_unlocks[*]:-} " in
                *" $u "*) kind=filename; secret="$RANGE_TFTP_FILE" ;;
            esac
            case " ${passphrase_unlocks[*]:-} " in
                *" $u "*) kind=passphrase; secret="$CHAIN_PASSPHRASE" ;;
            esac
            case "$u" in
                redis-open)   add_param "$uh" "redis_secret=${secret}"; add_param "$uh" "redis_secret_kind=${kind}"; add_intel "$uh" redis-open ;;
                rsync-module) add_param "$uh" "rsync_secret=${secret}"; add_param "$uh" "rsync_secret_kind=${kind}"; add_intel "$uh" rsync-module ;;
                mqtt-open)    add_param "$uh" "mqtt_secret=${secret}";  add_param "$uh" "mqtt_secret_kind=${kind}";  add_intel "$uh" mqtt-open ;;
            esac
            ;;
    esac
done

# hidden-path drawn as the filename producer names the file as well as the
# account, because the page it sits behind is the operations page and both facts
# are on it.
case " ${filename_unlocks[*]:-} " in
    *" hidden-path "*)
        [ -n "${UNLOCK_HOST[hidden-path]:-}" ] \
            && add_param "${UNLOCK_HOST[hidden-path]}" "leak_filename=${RANGE_TFTP_FILE}" ;;
esac

# Every FTP service that carries no unlock asks for a login it will not give up,
# which is what stops a range with three FTP hosts being three free findings.
for h in $( by_profile ftp ); do
    case " ${TARGET_INTEL[$h]} " in
        *" anon-ftp "*) ;;
        *) add_param "$h" "ftp_anon=no" ;;
    esac
done

# The proxy and the message broker are open by their own configuration rather
# than because the plan placed something on them, so their tokens are recorded
# wherever they run. A learner who finds an open proxy has found one whether or
# not the chain needed it.
for h in $( by_profile proxy ); do add_intel "$h" open-proxy; done
for h in $( by_profile mqtt );  do add_intel "$h" mqtt-open; done
for h in $( by_profile redis ); do add_intel "$h" redis-open; done
for h in $( by_profile rsync ); do add_intel "$h" rsync-module; done
for h in $( by_profile snmp );  do add_intel "$h" snmp-public; done

# Telnet hosts: every one claims a device family from the organisation's own
# equipment list in its login banner, and two thirds of them still carry the
# credential that family ships with. The field manual prints the table, so a
# learner who reads a banner naming one of them confirms it in a single login.
telnet_hosts=( $( by_profile telnet ) )
cred_placed=0
for h in "${telnet_hosts[@]}"; do
    rand_pick ${ORG_FAMILIES[$ORG]}; fam="$RAND"
    add_param "$h" "family=${fam}"
    rand_range 1 9; TARGET_HOSTNAME["$h"]="${ORG_PREFIX[$ORG]}-${fam}${RAND}"
    if rand_chance 2 3; then
        add_param "$h" "default_cred=${DEFAULT_CRED[$fam]}"
        add_intel "$h" default-cred
        cred_placed=1
    fi
    case " ${TARGET_INTEL[$h]} " in *" weak-telnet-pass "*) cred_placed=1 ;; esac
done
if [ "$cred_placed" -eq 0 ] && [ "${#telnet_hosts[@]}" -gt 0 ]; then
    h="${telnet_hosts[0]}"
    rand_pick ${ORG_FAMILIES[$ORG]}; fam="$RAND"
    add_param "$h" "default_cred=${DEFAULT_CRED[$fam]}"
    add_intel "$h" default-cred
fi

# DNS: the zone names every live segment's gateway and every host in the range,
# and it allows a transfer. A learner who tries dig AXFR is handed the map in one
# command, which is how it works in the field and is why the item is worth as
# much as the map it replaces.
dns_hosts=( $( by_profile dns ) )
for h in "${dns_hosts[@]}"; do
    add_param "$h" "zone=${RANGE_ZONE}"
    add_intel "$h" zone-transfer
done

# ---------------------------------------------------------------------------
# 6b. The decoys.
#
# Every one of these is a claim that looks like a finding and is not, and every
# one of them is checkable in a single command. They are here because the
# penalty half of the scoring existed and was never exercised: a learner who
# reports what they READ rather than what they PROBED should lose marks for it,
# and until now there was almost nothing on the range to read.

RANGE_DECOYS=""
add_decoy() { RANGE_DECOYS="${RANGE_DECOYS:+$RANGE_DECOYS }$1"; }

# Two names in the zone for addresses that hold nothing. The transfer is still
# the shortcut it always was; what it hands over is a records file and not a host
# list, and the difference costs two host penalties to anyone who forgets it.
RANGE_STALE_A=""
if [ "${#dns_hosts[@]}" -gt 0 ] && rand_chance 2 3; then
    stale=""
    for (( i = 0; i < 2; i++ )); do
        s="${SEGMENTS[$(( ${#SEGMENTS[@]} - 1 ))]}"
        rand "${#SEGMENTS[@]}"; s="${SEGMENTS[$RAND]}"
        base="${SEG_SUBNET[$s]%.0/24}"
        for (( t = 0; t < 40; t++ )); do
            rand_range 2 253; o="$RAND"
            cand="${base}.${o}"
            clash=0
            for h in "${HOSTS[@]}"; do [ "${TARGET_IP[$h]}" = "$cand" ] && clash=1; done
            [ "$cand" = "$ATTACKER_IP" ] && clash=1
            [ "$o" = 1 ] && clash=1
            case " $stale " in *" $cand "*) clash=1 ;; esac
            [ "$clash" -eq 0 ] && { stale="${stale:+$stale }$cand"; break; }
        done
    done
    RANGE_STALE_A="$stale"
    [ -n "$RANGE_STALE_A" ] && add_decoy stale-dns
fi

# An administratively-down interface on the SNMP host, holding an address in a
# block that is routed nowhere. It appears in the address table exactly as a live
# interface does, and the block it names is not a segment.
RANGE_GHOST_NET=""
snmp_hosts=( $( by_profile snmp ) )
if [ "${#snmp_hosts[@]}" -gt 0 ] && rand_chance 2 3; then
    draw_third; RANGE_GHOST_NET="${AS}.${second}.${THIRD}.0/24"
    gh="${snmp_hosts[0]}"
    add_param "$gh" "ghost_net=${RANGE_GHOST_NET}"
    add_intel "$gh" snmp-map
    add_decoy snmp-ghost
fi

http_hosts=( $( by_profile http ) )
if [ "${#http_hosts[@]}" -gt 0 ] && rand_chance 1 2; then
    host_running http; rh="$RAND"
    rand_pick "${HIDDEN_PATHS[@]}"; rp="$RAND"
    # A path the index does not link to and the server does not serve either. The
    # finding is what a GET returns, not what a text file asserts.
    case " ${TARGET_PARAM[$rh]} " in
        *" hidden_path=${rp} "*) ;;
        *) add_param "$rh" "robots_path=${rp}"; add_decoy robots-404 ;;
    esac
fi

# One web host that announces no version. lighttpd is pinned for it because
# darkhttpd has no option to change its Server header, so the only way to mask
# one there would be to put something in front of it.
if [ "${#http_hosts[@]}" -gt 0 ] && rand_chance 1 3; then
    host_running http; mh="$RAND"
    add_param "$mh" "masked_banner=yes"
    TARGET_IMPL["$mh"]=lighttpd
    add_decoy masked-banner
fi

# The token from an environment that no longer exists. It is shaped exactly like
# a real one, it matches no milestone this range planted, and the file it sits in
# says so in its first line.
RANGE_DECOY_FLAG=""
if [ -n "$anon_ftp" ] && rand_chance 1 2; then
    rand 65536; da="$RAND"; rand 65536; db="$RAND"
    printf -v RANGE_DECOY_FLAG '%s{staging-%04x%04x}' "$FLAG_PREFIX" "$da" "$db"
    add_param "$anon_ftp" "decoy_flag=${RANGE_DECOY_FLAG}"
    add_decoy decoy-flag
fi

# One router that does not answer a traceroute's expiring probe. The hop shows as
# a gap and the distance past it has to be counted rather than read. r1 is never
# the one: a gap at the first hop is a range where traceroute does not work at
# all, which teaches nothing.
RANGE_NO_TTL_ROUTER=""
if [ "${#ROUTERS[@]}" -gt 1 ] && rand_chance 1 3; then
    rand_range 2 "${#ROUTERS[@]}"; RANGE_NO_TTL_ROUTER="r${RAND}"
    add_decoy no-time-exceeded
fi

# A printer and a monitoring agent name themselves, so the strings they answer
# with are drawn here rather than left in the profile script where every range
# would share them.
for h in $( by_profile jetdirect ); do
    rand_pick "LaserJet 4250" "LaserJet M607" "OfficeJet Pro X476" "ColorJet CP4525"
    add_param "$h" "printer_model=$RAND"
    # No leading zero. `07.150.4` and `7.150.4` are different strings to the
    # version comparison, and a learner who typed the second after reading the
    # first would be marked wrong for a difference that is not one.
    rand_range 1 9; a="$RAND"; rand_range 100 199; b="$RAND"; rand_range 0 9; c="$RAND"
    add_param "$h" "printer_firmware=${a}.${b}.${c}"
done
for h in $( by_profile monitor ); do
    rand_range 1 4; a="$RAND"; rand_range 0 9; b="$RAND"
    add_param "$h" "monitor_version=${a}.${b}"
done

# ---------------------------------------------------------------------------
# 5b. The chain: which machines it runs through, and the tokens on each of them.
#
# The survey half of this range asks what is out there. This half asks what one
# of those services is good for, and it is the half that ends on a win rather
# than on a number.
#
# Every step is a login with a credential found somewhere else, and the last one
# is a sudo rule that should never have been written. Nothing here is an exploit:
# every door on the chain opens because of a configuration a defender fixes by
# editing a file.
#
# THE VAULT'S KEY IS SPLIT ACROSS TWO BRANCHES ON PURPOSE. The private key sits
# on the foothold host, which needs the telnet credential; its passphrase sits on
# the anonymous share, which needs nothing but a scan. One branch alone opens
# nothing, so a learner who got lucky down one arm still has to work the other.

draw_token() {   # draw_token <milestone name> -> $TOKEN
    local a b
    rand 65536; a="$RAND"
    rand 65536; b="$RAND"
    printf -v TOKEN '%s{%s-%04x%04x}' "$FLAG_PREFIX" "$1" "$a" "$b"
}

# The foothold is a telnet host the learner can actually get into, so it is drawn
# from the telnet hosts that were given a credential rather than from all of
# them. Section 5 guarantees at least one exists.
chain_candidates=()
for h in "${telnet_hosts[@]}"; do
    case " ${TARGET_INTEL[$h]} " in
        *" default-cred "*|*" weak-telnet-pass "*) chain_candidates+=( "$h" ) ;;
    esac
done
[ "${#chain_candidates[@]}" -gt 0 ] || chain_candidates=( "${telnet_hosts[0]}" )
rand "${#chain_candidates[@]}"; CHAIN_FOOTHOLD="${chain_candidates[$RAND]}"

# At four layers the pivot is a host already running SSH, which the forced mix
# guarantees. Using a drawn host rather than a second dedicated container is what
# keeps the pivot free: its SSH port was already an open port the survey scores,
# and the chain only adds a key to it.
CHAIN_PIVOT=""
if [ "$depth" -ge 4 ]; then
    ssh_hosts=( $( by_profile ssh ) )
    if [ "${#ssh_hosts[@]}" -gt 0 ]; then
        rand "${#ssh_hosts[@]}"; CHAIN_PIVOT="${ssh_hosts[$RAND]}"
    else
        # The forced mix should make this unreachable. Losing a layer is a worse
        # outcome than failing the draw, so say so rather than shipping a range
        # whose depth silently does not match its shape.
        echo "shape $shape wants a 4-layer chain and no host drew the ssh profile" >&2
        exit 1
    fi
fi

# The private key that spawn.sh generates in the foothold's home directories is a
# finding in its own right: a passphrase-protected key with a note beside it
# saying which machine it opens is exactly what an operator leaves behind, and a
# learner who reaches that shell and reports it has found something. It is
# recorded here so the generator's view of the range agrees with the one the
# containers will hold.
[ "$depth" -ge 3 ] && add_intel "$CHAIN_FOOTHOLD" leaked-key

# The steps, in the order a learner walks them: milestone token, then the machine
# it is read off. The vault holds the last milestone and the flag both, because
# reaching the vault and reading what is on it are two different things: the
# second needs the sudo rule.
CHAIN_STEPS=( "foothold:${CHAIN_FOOTHOLD}" )
[ -n "$CHAIN_PIVOT" ] && CHAIN_STEPS+=( "pivot:${CHAIN_PIVOT}" )
if [ "$depth" -ge 3 ]; then
    CHAIN_STEPS+=( "vault:${VAULT}" )
    CHAIN_FLAG_MACHINE="$VAULT"
else
    # Two layers: one login, and the flag behind a sudo rule on that same host.
    CHAIN_FLAG_MACHINE="$CHAIN_FOOTHOLD"
fi

# The machine whose address is allowed through the filter in front of the vault.
# It is the last machine on the chain before the vault, so opening the vault
# means standing on that machine and not merely knowing its key.
CHAIN_VAULT_FROM=""
[ "$depth" -ge 3 ] && CHAIN_VAULT_FROM="${CHAIN_PIVOT:-$CHAIN_FOOTHOLD}"

# One token per step, plus the flag.
declare -A CHAIN_TOKEN=()
for step in "${CHAIN_STEPS[@]}"; do
    draw_token "${step%%:*}"; CHAIN_TOKEN["${step%%:*}"]="$TOKEN"
done
draw_token flag; CHAIN_FLAG_TOKEN="$TOKEN"

# The passphrase was drawn in section 6, before the unlocks were placed, because
# the machines that carry it are drawn rather than fixed. THE KEY IT OPENS IS ON
# THE FOOTHOLD HOST, behind the telnet credential, and the passphrase is on
# whichever service the passphrase producer was placed on: an anonymous share, a
# key-value store with no authentication, a backup module, a retained message on
# a broker. Two entirely different pieces of work reach the two halves, which is
# what stops the chain being a corridor: a learner who cracked the telnet account
# and enumerated nothing else has a key they cannot use.
#
# CHAIN_PASS_UNLOCK names the producer the solver should walk, which is the first
# one the plan placed. A learner may use any of them.
CHAIN_PASS_UNLOCK=""
CHAIN_PASS_HOST=""
if [ "$depth" -ge 3 ]; then
    for u in ${passphrase_unlocks[@]+"${passphrase_unlocks[@]}"}; do
        [ -n "${UNLOCK_HOST[$u]:-}" ] || continue
        CHAIN_PASS_UNLOCK="$u"; CHAIN_PASS_HOST="${UNLOCK_HOST[$u]}"
        break
    done
fi

# ---------------------------------------------------------------------------
# 5c. Is this range winnable?
#
# With the chain drawn rather than written by hand, a draw can in principle
# produce a range whose only way in runs through something that is not there, and
# a learner would lose an hour to it before anyone found out. This is the cheap
# half of the answer: a reachability check over what was drawn, costing no
# containers, so it rides the seed sweep in selftest.sh for free. The expensive
# half is scripts/solve.sh, which plays the chain against a range that is
# actually running.
chain_unwinnable() {   # -> prints why, or nothing
    local step m h in_hosts
    # Every step's machine has to exist.
    for step in "${CHAIN_STEPS[@]}"; do
        m="${step#*:}"
        [ "$m" = "$VAULT" ] && continue
        in_hosts=0
        for h in "${HOSTS[@]}"; do [ "$h" = "$m" ] && in_hosts=1; done
        [ "$in_hosts" -eq 1 ] || { echo "step ${step%%:*} names $m, which is not a drawn host"; return; }
    done
    # The foothold needs a credential a learner can obtain.
    case " ${TARGET_INTEL[$CHAIN_FOOTHOLD]} " in
        *" default-cred "*|*" weak-telnet-pass "*) ;;
        *) echo "the foothold host $CHAIN_FOOTHOLD carries no obtainable credential"; return ;;
    esac
    # weak-telnet-pass is only obtainable once something has named the account.
    # A foothold whose only credential is that one, on a range where no producer
    # of the account name was placed, is a dictionary attack with no dictionary
    # entry point: a finding no learner can make.
    case " ${TARGET_INTEL[$CHAIN_FOOTHOLD]} " in
        *" default-cred "*) ;;
        *) [ -n "${UNLOCK_HOST[${account_unlocks[0]}]:-}" ] \
               || { echo "the foothold needs the shared account and nothing on this range names it"; return; } ;;
    esac
    # Three layers and deeper: the vault, and the split key that opens it. The
    # passphrase has to be somewhere a learner can read it, which means a
    # producer for it was drawn AND landed on a host running that service.
    if [ "$depth" -ge 3 ]; then
        [ -n "$VAULT_NET" ]       || { echo "a ${depth}-layer chain drew no vault segment"; return; }
        [ -n "$CHAIN_VAULT_FROM" ] || { echo "no machine is permitted through the vault filter"; return; }
        [ -n "$CHAIN_PASSPHRASE" ] || { echo "no passphrase was drawn for the vault key"; return; }
        [ -n "$CHAIN_PASS_HOST" ] || { echo "the key passphrase was placed on no machine"; return; }
    fi
    if [ "$depth" -ge 4 ]; then
        [ -n "$CHAIN_PIVOT" ] || { echo "a 4-layer chain drew no pivot host"; return; }
    fi
    # A winnable chain prints nothing and must still return success. Without
    # this the function's last statement is a test that is false on every range
    # shallower than four layers, the command substitution below inherits that
    # status, and `set -e` kills the generator on a range with nothing wrong
    # with it.
    return 0
}
why="$( chain_unwinnable )"
if [ -n "$why" ]; then
    echo "seed $seed at tier $tier drew an unwinnable chain: $why" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 6. The routing tables.
#
# Plain Linux routers with ip_forward and generated static routes, not FRR:
# nothing in a scanning range needs a routing protocol, and the tables have to be
# predictable for the invariant sweep to check them. r1 carries no default route,
# so a probe to a /24 that does not exist comes straight back as an ICMP network
# unreachable instead of being forwarded into nothing.

# Every CIDR reachable through <router> from ABOVE it: the segments and dead
# ranges it serves, and, for each router hanging off it, the link to that router
# plus everything below that in turn. The link between <router> and its own
# parent is not in the set, because the parent has it connected.
#
# Including the router-to-router links is load-bearing and was missed the first
# time. Without them r1 holds no route to the r2-to-r3 link, so when r3 answers a
# traceroute with a TTL-exceeded sourced from its address on that link, r1 drops
# it on reverse-path filtering and the hop shows as `*`. The address is a scored
# router interface, so it also has to be reachable for a learner to confirm it at
# all: an interface a traceroute names and a ping cannot reach is a finding
# nobody can check.
subnets_below() {   # subnets_below <router> -> every CIDR reachable through it
    local r="$1" out="" s d c t
    for s in "${SEGMENTS[@]}"; do
        [ "$s" = "seg0" ] && continue
        [ "${SEG_ROUTER[$s]}" = "$r" ] && out="${out:+$out }${SEG_SUBNET[$s]}"
    done
    for d in "${DEAD_RANGES[@]}"; do
        [ "${DEAD_ROUTER[$d]}" = "$r" ] && out="${out:+$out }${DEAD_SUBNET[$d]}"
    done
    # The vault's subnet is routed like any other, and the filter that guards it
    # is a FORWARD rule on its own router rather than a missing route. A missing
    # route would answer a probe with a network-unreachable from whichever router
    # ran out of table, which says the subnet does not exist; the filter answers
    # with an administratively-prohibited from the router that serves it, which
    # says the subnet exists and something decided not to let this packet in.
    # Only the second of those is a door a learner can go looking for.
    [ -n "$VAULT_NET" ] && [ "$VAULT_ROUTER" = "$r" ] && out="${out:+$out }${VAULT_NET}"
    for c in "${ROUTERS[@]}"; do
        [ "${ROUTER_PARENT[$c]:-}" = "$r" ] || continue
        for t in "${TRANSITS[@]}"; do
            [ "${TRANSIT_A[$t]}" = "$r" ] && [ "${TRANSIT_B[$t]}" = "$c" ] \
                && out="${out:+$out }${TRANSIT_SUBNET[$t]}"
        done
        out="${out:+$out }$( subnets_below "$c" )"
    done
    echo "$out"
}

# Each router's interfaces, as "<ifname>:<cidr>" pairs, and its static routes, as
# "<cidr>>via<nexthop>" pairs.
declare -A ROUTER_IFACES=() ROUTER_ROUTES=()
for r in "${ROUTERS[@]}"; do ROUTER_IFACES["$r"]=""; ROUTER_ROUTES["$r"]=""; done

add_iface() { ROUTER_IFACES["$1"]="${ROUTER_IFACES[$1]:+${ROUTER_IFACES[$1]} }$2"; }
add_route() { ROUTER_ROUTES["$1"]="${ROUTER_ROUTES[$1]:+${ROUTER_ROUTES[$1]} }$2"; }

add_iface r1 "${AS}-seg0:${ATT_GW}/24"
for s in "${SEGMENTS[@]}"; do
    [ "$s" = "seg0" ] && continue
    add_iface "${SEG_ROUTER[$s]}" "${AS}-${s}:${SEG_GW[$s]}/24"
done
for d in "${DEAD_RANGES[@]}"; do
    add_iface "${DEAD_ROUTER[$d]}" "${AS}-${d}:${DEAD_GW[$d]}/24"
done
[ -n "$VAULT_NET" ] && add_iface "$VAULT_ROUTER" "${AS}-${VAULT}:${VAULT_GW}/24"
for t in "${TRANSITS[@]}"; do
    add_iface "${TRANSIT_A[$t]}" "${AS}-${TRANSIT_B[$t]}:${TRANSIT_A_IP[$t]}/30"
    add_iface "${TRANSIT_B[$t]}" "${AS}-${TRANSIT_A[$t]}:${TRANSIT_B_IP[$t]}/30"
done

for t in "${TRANSITS[@]}"; do
    a="${TRANSIT_A[$t]}"; b="${TRANSIT_B[$t]}"
    # Downstream: everything below the child, routed through it.
    for cidr in $( subnets_below "$b" ); do
        add_route "$a" "${cidr}>${TRANSIT_B_IP[$t]}"
    done
    # Upstream: a default route back towards the attacker.
    add_route "$b" "default>${TRANSIT_A_IP[$t]}"
done

# ---------------------------------------------------------------------------
# 7. What the learner is told at spawn.

# The opening is drawn from the tier's list, so two spawns at one tier differ in
# the first move as well as in the map. Every kind on a tier's list is the same
# amount of work; the kind decides where that work starts.
#
# RANGE_GIVEN is display text and RANGE_GIVEN_NETS is the scoring rule, and they
# are two fields rather than one because they stopped being the same thing. A
# subnet is excluded from the scoring only when it was handed over unambiguously:
# three candidate blocks of which two do not exist is a list to check, not an
# answer, so it names real subnets and excludes none of them.
rand_pick ${TIER_OPENINGS[$tier]}; opening="$RAND"

# A tier can list an opening that a particular range cannot support. Falling back
# rather than redrawing keeps the draw sequence a fixed length, which is what
# makes a (tier, seed) pair reproducible.
[ "$opening" = dns ] && [ "${#dns_hosts[@]}" -eq 0 ] && opening=prefix

live_nets=()
for s in "${SEGMENTS[@]}"; do
    [ "$s" = "seg0" ] && continue
    live_nets+=( "${SEG_SUBNET[$s]}" )
done

RANGE_GIVEN=""
RANGE_GIVEN_NETS=""
case "$opening" in
    segs)
        RANGE_GIVEN="${live_nets[*]}"
        RANGE_GIVEN_NETS="${live_nets[*]}"
        ;;
    candidates)
        cand=( "${live_nets[@]}" )
        for (( c = 0; c < 2; c++ )); do
            draw_third; cand+=( "${AS}.${second}.${THIRD}.0/24" )
        done
        rand_shuffle cand
        RANGE_GIVEN="${cand[*]}"
        ;;
    count)
        RANGE_GIVEN="${RANGE_PREFIX} with ${#live_nets[@]} live segment(s) in it"
        ;;
    prefix)
        RANGE_GIVEN="$RANGE_PREFIX"
        ;;
    dns)
        RANGE_GIVEN="${TARGET_IP[${dns_hosts[0]}]} is authoritative for ${RANGE_ZONE}"
        ;;
    nothing)
        RANGE_GIVEN=""
        ;;
esac

# ---------------------------------------------------------------------------
# 8. Budget and sanity, before anything is written.

ncontainers=$(( 2 + ${#ROUTERS[@]} + ${#HOSTS[@]} ))
[ -n "$VAULT_NET" ] && ncontainers=$(( ncontainers + 1 ))
if [ "$ncontainers" -gt "$MAX_CONTAINERS" ]; then
    echo "generated range needs $ncontainers containers, over the budget of $MAX_CONTAINERS" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 9. Write it out.
#
# Associative arrays are emitted key by key in a driving list's order rather than
# with a bare `declare -p`, so that the file is byte-identical for a given
# (tier, seed) pair and legible when reveal.sh or a bug report quotes it.
# RANGE_SPAWNED_AT is deliberately NOT in here: it is a clock reading, and a file
# holding one could not be compared between two runs of the same seed. spawn.sh
# writes it to state/spawned_at instead.

mkdir -p "$STATE_DIR"

# -g is load-bearing, not decoration. Every consumer sources this file from
# inside lib.sh's load_topology function, and a bare `declare` inside a function
# creates a LOCAL variable: without -g every associative array here would go out
# of scope the moment load_topology returned, and the caller's next line would
# read an unset address.
emit_map() {   # emit_map <array-name> <key...>
    local name="$1"; shift
    local -n _m="$name"
    printf 'declare -gA %s=(' "$name"
    local k
    for k in "$@"; do printf ' [%s]="%s"' "$k" "${_m[$k]:-}"; done
    printf ' )\n'
}

{
    printf '# Generated by scripts/generate.sh. Do not edit: Spawn overwrites it.\n'
    printf '# A (tier, seed) pair reproduces this file byte for byte.\n\n'
    printf 'RANGE_SEED=%s\n'   "$seed"
    printf 'RANGE_TIER=%s\n'   "$tier"
    printf 'RANGE_SHAPE=%s\n'  "$shape"
    printf 'RANGE_MUTATOR=%s\n' "$MUTATOR"
    printf 'RANGE_ORG=%s\n'    "$ORG"
    printf 'RANGE_ORG_NAME="%s"\n'   "${ORG_NAME[$ORG]}"
    printf 'RANGE_ORG_PREFIX=%s\n'   "${ORG_PREFIX[$ORG]}"
    printf 'RANGE_ORG_TEAM="%s"\n'   "${ORG_TEAM[$ORG]}"
    printf 'RANGE_ORG_SITES="%s"\n'  "${ORG_SITES[$ORG]}"
    printf 'RANGE_ORG_DROP="%s"\n'   "${ORG_DROP[$ORG]}"
    printf 'RANGE_ZONE=%s\n'   "$RANGE_ZONE"
    printf 'RANGE_PREFIX=%s\n' "$RANGE_PREFIX"
    printf 'RANGE_OPENING=%s\n' "$opening"
    printf 'RANGE_GIVEN="%s"\n' "$RANGE_GIVEN"
    printf 'RANGE_GIVEN_NETS="%s"\n' "$RANGE_GIVEN_NETS"
    printf '\n'
    printf 'ATT_SUBNET=%s\n'  "$ATT_SUBNET"
    printf 'ATTACKER_IP=%s\n' "$ATTACKER_IP"
    printf 'ATT_GW=%s\n'      "$ATT_GW"
    printf '\n'
    printf 'SEGMENTS=(%s)\n'    "${SEGMENTS[*]}"
    printf 'SEG_LOCAL=seg0\n'
    emit_map SEG_SUBNET "${SEGMENTS[@]}"
    emit_map SEG_BRIDGE "${SEGMENTS[@]}"
    emit_map SEG_ROUTER "${SEGMENTS[@]}"
    emit_map SEG_GW     "${SEGMENTS[@]}"
    emit_map SEG_HOPS   "${SEGMENTS[@]}"
    emit_map SEG_HOSTS  "${SEGMENTS[@]}"
    printf '\n'
    printf 'DEAD_RANGES=(%s)\n' "${DEAD_RANGES[*]:-}"
    if [ "${#DEAD_RANGES[@]}" -gt 0 ]; then
        emit_map DEAD_SUBNET "${DEAD_RANGES[@]}"
        emit_map DEAD_BRIDGE "${DEAD_RANGES[@]}"
        emit_map DEAD_ROUTER "${DEAD_RANGES[@]}"
        emit_map DEAD_GW     "${DEAD_RANGES[@]}"
        emit_map DEAD_ANSWER "${DEAD_RANGES[@]}"
    else
        printf 'declare -gA DEAD_SUBNET=() DEAD_BRIDGE=() DEAD_ROUTER=() DEAD_GW=() DEAD_ANSWER=()\n'
    fi
    printf '\n'
    printf 'ROUTERS=(%s)\n' "${ROUTERS[*]}"
    emit_map ROUTER_PARENT "${ROUTERS[@]}"
    emit_map ROUTER_IFACES "${ROUTERS[@]}"
    emit_map ROUTER_ROUTES "${ROUTERS[@]}"
    printf '\n'
    printf 'TRANSITS=(%s)\n' "${TRANSITS[*]:-}"
    if [ "${#TRANSITS[@]}" -gt 0 ]; then
        emit_map TRANSIT_SUBNET "${TRANSITS[@]}"
        emit_map TRANSIT_A      "${TRANSITS[@]}"
        emit_map TRANSIT_B      "${TRANSITS[@]}"
        emit_map TRANSIT_A_IP   "${TRANSITS[@]}"
        emit_map TRANSIT_B_IP   "${TRANSITS[@]}"
    else
        printf 'declare -gA TRANSIT_SUBNET=() TRANSIT_A=() TRANSIT_B=() TRANSIT_A_IP=() TRANSIT_B_IP=()\n'
    fi
    printf '\n'
    printf 'HOSTS=(%s)\n' "${HOSTS[*]}"
    emit_map TARGET_IP       "${HOSTS[@]}"
    emit_map TARGET_SEG      "${HOSTS[@]}"
    emit_map TARGET_PROFILE  "${HOSTS[@]}"
    emit_map TARGET_SERVICES "${HOSTS[@]}"
    emit_map TARGET_IMPL     "${HOSTS[@]}"
    emit_map TARGET_CLASS    "${HOSTS[@]}"
    emit_map TARGET_PORTS    "${HOSTS[@]}"
    emit_map TARGET_ICMP     "${HOSTS[@]}"
    emit_map TARGET_SHUT     "${HOSTS[@]}"
    emit_map TARGET_FILTERED "${HOSTS[@]}"
    emit_map TARGET_INTEL    "${HOSTS[@]}"
    emit_map TARGET_PARAM    "${HOSTS[@]}"
    emit_map TARGET_HOSTNAME "${HOSTS[@]}"
    printf '\n'
    printf 'RANGE_LEAK_ACCOUNT=%s\n' "$RANGE_LEAK_ACCOUNT"
    printf 'RANGE_WEAK_PASS=%s\n'    "$RANGE_WEAK_PASS"
    printf 'RANGE_TFTP_FILE=%s\n'    "$RANGE_TFTP_FILE"
    printf 'RANGE_NO_SERVICE_HOST=%s\n' "$no_service_host"
    printf 'RANGE_CONTAINERS=%s\n'   "$ncontainers"
    printf '\n'
    # The chain. CHAIN_STEPS is ordered, and the order is the order a learner
    # walks it, so spawn.sh plants each machine's key for the next one by reading
    # this list front to back.
    printf 'RANGE_DEPTH=%s\n' "$depth"
    printf 'CHAIN_STEPS=(%s)\n' "${CHAIN_STEPS[*]}"
    printf 'CHAIN_FOOTHOLD=%s\n'      "$CHAIN_FOOTHOLD"
    printf 'CHAIN_PIVOT=%s\n'         "${CHAIN_PIVOT:-}"
    printf 'CHAIN_FLAG_MACHINE=%s\n'  "$CHAIN_FLAG_MACHINE"
    printf 'CHAIN_VAULT_FROM=%s\n'    "${CHAIN_VAULT_FROM:-}"
    printf 'CHAIN_FLAG_TOKEN=%s\n'    "$CHAIN_FLAG_TOKEN"
    printf 'CHAIN_PASSPHRASE=%s\n'    "${CHAIN_PASSPHRASE:-}"
    printf 'CHAIN_PASS_UNLOCK=%s\n'   "${CHAIN_PASS_UNLOCK:-}"
    printf 'CHAIN_PASS_HOST=%s\n'     "${CHAIN_PASS_HOST:-}"
    printf 'RANGE_UNLOCKS="%s"\n'     "${unlocks[*]}"
    if [ "${#placed_unlocks[@]}" -gt 0 ]; then
        emit_map UNLOCK_HOST "${placed_unlocks[@]}"
    else
        printf 'declare -gA UNLOCK_HOST=()\n'
    fi
    if [ "${#CHAIN_STEPS[@]}" -gt 0 ]; then
        local_keys=()
        for step in "${CHAIN_STEPS[@]}"; do local_keys+=( "${step%%:*}" ); done
        emit_map CHAIN_TOKEN "${local_keys[@]}"
    else
        printf 'declare -gA CHAIN_TOKEN=()\n'
    fi
    printf '\n'
    printf 'VAULT_NET="%s"\n'    "${VAULT_NET:-}"
    printf 'VAULT_BRIDGE="%s"\n' "${VAULT_BRIDGE:-}"
    printf 'VAULT_ROUTER="%s"\n' "${VAULT_ROUTER:-}"
    printf 'VAULT_GW="%s"\n'     "${VAULT_GW:-}"
    printf 'VAULT_IP="%s"\n'     "${VAULT_IP:-}"
    printf '\n'
    printf 'RANGE_DECOYS="%s"\n'      "$RANGE_DECOYS"
    printf 'RANGE_STALE_A="%s"\n'     "$RANGE_STALE_A"
    printf 'RANGE_GHOST_NET="%s"\n'   "$RANGE_GHOST_NET"
    printf 'RANGE_DECOY_FLAG="%s"\n'  "$RANGE_DECOY_FLAG"
    printf 'RANGE_NO_TTL_ROUTER="%s"\n' "$RANGE_NO_TTL_ROUTER"
} > "$TOPO_ENV"

# reveal.sh refuses to print the key until score.sh has run against this spawn.
# A fresh range clears that marker, and the previous range's findings copy with
# it, so nothing from the last seed can be read as belonging to this one.
rm -f "$SCORED_MARKER" "$FINDINGS_COPY"

echo "SEED $seed TIER $tier SHAPE $shape MUTATOR $MUTATOR"
