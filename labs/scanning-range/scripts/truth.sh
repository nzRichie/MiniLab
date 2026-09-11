#!/usr/bin/env bash
# Read this range's ground truth back off the containers that are running.
# Sourced by score.sh and reveal.sh; no side effects.
#
# NOTHING HERE OPENS state/topology.env, and that is the rule the whole range
# turns on. Ground truth is re-derived at scoring time by inspecting the live
# containers, never read from a key file written at spawn, so the scorer cannot
# disagree with the network the learner just scanned. A service that failed to
# start is a port that is not open, not a finding the learner missed; a host that
# lost its address is not a host; and a range whose generator drew something its
# spawn could not build is marked on what was actually built.
#
# What each fact is read from:
#   the exercise's parameters   /etc/minilabs/range.env on the attacker
#   addresses and prefix lengths `ip -brief -4 addr` in each container, UP only
#   which segments are live      a /24 gateway with at least one host in it
#   which are dead               a /24 gateway with none
#   distance in hops             the router graph, walked from the router on the
#                                attacker's own segment
#   open ports, services, versions  /etc/minilabs/profile.d/ in each host
#   intel items                  /etc/minilabs/intel in each host

# --- what truth_load fills in ----------------------------------------------
T_SEED="" T_TIER="" T_GIVEN="" T_SPAWNED_AT="" T_SHAPE=""
T_OPENING="" T_DEPTH="" T_VAULT_NET="" T_MUTATOR="" T_ORG=""
T_ATTACKER_IP="" T_ATT_SUBNET="" T_ATT_GW=""
declare -a T_SEGMENTS=() T_DEAD=() T_ROUTER_IPS=() T_HOSTS=() T_PORTS=()
# The subnets that were handed over unambiguously, and so are worth nothing. It
# is a list rather than the single string it used to be because the openings
# stopped handing over exactly one thing: `segs` hands over every live segment,
# and `candidates` hands over a list of blocks of which two do not exist and
# therefore excludes nothing at all.
declare -a T_GIVEN_NETS=()
declare -A T_SEG_HOPS=() T_SEG_GW=() T_SEG_ROUTER=()
declare -A T_SERVICE=() T_VERSION=() T_ACCEPT=()
declare -A T_INTEL=() T_HOST_SEG=() T_ICMP=() T_SHUT=() T_CLASS=()
# Ports that are dropped rather than refused on a host that refuses everything
# else. They are not open and they are not scored as such; they are here so that
# Reveal can say why a scan reported `filtered` on three ports of one machine.
declare -A T_FILTERED=()
declare -A T_ROUTER_IF=()      # router token -> "cidr cidr ..."
# The chain's tokens, milestone name -> token, read off the machines that hold
# them. `flag` is one of the names.
declare -A T_FLAG_TOKEN=()

_net_of() {   # <a.b.c.d/len> -> network CIDR
    local a b c d len ip="${1%/*}"
    len="${1#*/}"
    IFS=. read -r a b c d <<< "$ip"
    case "$len" in
        24) echo "$a.$b.$c.0/24" ;;
        30) echo "$a.$b.$c.$(( d - d % 4 ))/30" ;;
        *)  echo "$a.$b.$c.$d/$len" ;;
    esac
}

truth_load() {
    local names token ctn line

    # Every global is cleared first. truth_load is called more than once in a
    # single selftest run, once per spawned range, and an append-only load
    # carried the previous range's ports and hosts into the next one's ground
    # truth: the scorer then looked for services on addresses that no longer
    # existed and reported versions as missing.
    T_SEED="" T_TIER="" T_GIVEN="" T_SPAWNED_AT="" T_SHAPE=""
    T_OPENING="" T_DEPTH="" T_VAULT_NET="" T_MUTATOR="" T_ORG=""
    T_ATTACKER_IP="" T_ATT_SUBNET="" T_ATT_GW=""
    T_SEGMENTS=() T_DEAD=() T_ROUTER_IPS=() T_HOSTS=() T_PORTS=() T_GIVEN_NETS=()
    T_SEG_HOPS=() T_SEG_GW=() T_SEG_ROUTER=()
    T_SERVICE=() T_VERSION=() T_ACCEPT=()
    T_INTEL=() T_HOST_SEG=() T_ICMP=() T_SHUT=() T_CLASS=() T_FILTERED=() T_ROUTER_IF=()
    T_FLAG_TOKEN=()

    mapfile -t names < <( docker ps --format '{{.Names}}' \
        | grep "^${CTN_PREFIX}" | sed "s/^${CTN_PREFIX}//" | sort )
    [ "${#names[@]}" -gt 0 ] || { echo "no range containers are running" >&2; return 1; }

    # The exercise's own parameters.
    local env_txt
    env_txt="$( docker exec "$ATTACKER_CTN" cat /etc/minilabs/range.env 2>/dev/null )" \
        || { echo "the attacker container holds no range.env; was this range spawned by spawn.sh?" >&2; return 1; }
    eval "$env_txt"
    T_SEED="${RANGE_SEED:-}"; T_TIER="${RANGE_TIER:-}"
    T_GIVEN="${RANGE_GIVEN:-}"; T_SPAWNED_AT="${RANGE_SPAWNED_AT:-}"
    T_OPENING="${RANGE_OPENING:-}"; T_DEPTH="${RANGE_DEPTH:-2}"
    T_VAULT_NET="${RANGE_VAULT_NET:-}"
    T_MUTATOR="${RANGE_MUTATOR:-}"; T_ORG="${RANGE_ORG_NAME:-}"
    # shellcheck disable=SC2206
    [ -n "${RANGE_GIVEN_NETS:-}" ] && T_GIVEN_NETS=( ${RANGE_GIVEN_NETS} )

    # Addresses, container by container.
    local routers=() hosts=()
    for token in "${names[@]}"; do
        case "$token" in
            r[0-9]*)   routers+=( "$token" ) ;;
            host[0-9]*) hosts+=( "$token" ) ;;
            attacker)  ;;
            *) continue ;;                        # the switch, the wiring helper
        esac
    done

    T_ATTACKER_IP="$( docker exec "$ATTACKER_CTN" ip -brief -4 addr show 2>/dev/null \
        | awk '$1 != "lo" && $2 == "UP" && $3 != "" {print $3; exit}' )"
    T_ATT_SUBNET="$( _net_of "$T_ATTACKER_IP" )"
    T_ATTACKER_IP="${T_ATTACKER_IP%/*}"

    # Every router interface, keyed by router, as network/address pairs. A /24 is
    # a segment or a dead range; a /30 is a link to another router.
    local -A gw_of_net=() router_of_net=()
    local -a transit_ips=()
    for token in "${routers[@]}"; do
        T_ROUTER_IF["$token"]=""
        while read -r cidr; do
            [ -n "$cidr" ] || continue
            local net; net="$( _net_of "$cidr" )"
            T_ROUTER_IF["$token"]="${T_ROUTER_IF[$token]:+${T_ROUTER_IF[$token]} }${cidr}"
            case "$cidr" in
                */24) gw_of_net["$net"]="${cidr%/*}"; router_of_net["$net"]="$token" ;;
                */30) transit_ips+=( "${cidr%/*}" ) ;;
            esac
        done < <( docker exec "$( ctn_of "$token" )" ip -brief -4 addr show 2>/dev/null \
                  | awk '$1 != "lo" && $2 == "UP" && $3 != "" {print $3}' )
    done

    # Every host's address, and which /24 it sits in. Only an interface that is
    # UP counts. The snmp-ghost decoy puts a second address on an
    # administratively-down veth, and that veth sorts ahead of the real one by
    # interface index, so reading the first address here recorded the ghost
    # 116.242.67.1 as the host. That made the host, its ports, its class and its
    # intel unfindable, turned the learner's correct finding for the real address
    # into a false positive, and demoted the segment the host sits in to a dead
    # range because nothing was left in it.
    local ip net
    for token in "${hosts[@]}"; do
        ip="$( docker exec "$( ctn_of "$token" )" ip -brief -4 addr show 2>/dev/null \
               | awk '$1 != "lo" && $2 == "UP" && $3 != "" {print $3; exit}' )"
        [ -n "$ip" ] || continue
        net="$( _net_of "$ip" )"; ip="${ip%/*}"
        T_HOSTS+=( "$ip" )
        T_HOST_SEG["$ip"]="$net"
    done

    # A /24 a router serves is a live segment when a host sits in it, and a dead
    # range when none does. The attacker's own segment is neither: it is on the
    # attacker's own interface, so it is not something a scan discovered.
    local n
    for n in "${!gw_of_net[@]}"; do
        [ "$n" = "$T_ATT_SUBNET" ] && { T_ATT_GW="${gw_of_net[$n]}"; continue; }
        # The vault's subnet is neither a live segment nor a dead range. It holds
        # a machine, so calling it dead would be a lie the scorer then penalised
        # a learner for contradicting; and the survey cannot reach it, so calling
        # it live would score a finding no scan could make. It is excluded from
        # the scoring in both directions, which is what lets the filter in front
        # of it answer honestly with an administratively-prohibited.
        [ -n "$T_VAULT_NET" ] && [ "$n" = "$T_VAULT_NET" ] && continue
        local occupied=0 h
        for h in "${T_HOSTS[@]}"; do [ "${T_HOST_SEG[$h]}" = "$n" ] && occupied=1; done
        if [ "$occupied" -eq 1 ]; then
            T_SEGMENTS+=( "$n" )
            T_SEG_GW["$n"]="${gw_of_net[$n]}"
            T_SEG_ROUTER["$n"]="${router_of_net[$n]}"
        else
            T_DEAD+=( "$n" )
        fi
    done
    # Sorted, so two runs of the scorer print the same order.
    [ "${#T_SEGMENTS[@]}" -gt 0 ] \
        && mapfile -t T_SEGMENTS < <( printf '%s\n' "${T_SEGMENTS[@]}" | sort -t. -k2,2n -k3,3n )
    [ "${#T_DEAD[@]}" -gt 0 ] && mapfile -t T_DEAD < <( printf '%s\n' "${T_DEAD[@]}" | sort -t. -k2,2n -k3,3n )

    # The router graph, walked outwards from the router on the attacker's own
    # segment. Two routers are adjacent when they share a /30, which is what a
    # traceroute walks and is therefore what SEG_HOPS has to agree with.
    local root=""
    for token in "${routers[@]}"; do
        [[ " ${T_ROUTER_IF[$token]} " == *" ${T_ATT_GW}/"* ]] && root="$token"
    done
    local -A depth=()
    [ -n "$root" ] && depth["$root"]=1
    local changed=1 a b
    while [ "$changed" -eq 1 ]; do
        changed=0
        for a in "${routers[@]}"; do
            [ -n "${depth[$a]:-}" ] || continue
            for b in "${routers[@]}"; do
                [ "$a" = "$b" ] && continue
                [ -n "${depth[$b]:-}" ] && continue
                # adjacent when some /30 network appears on both
                local ca cb
                for ca in ${T_ROUTER_IF[$a]}; do
                    [ "${ca#*/}" = 30 ] || continue
                    for cb in ${T_ROUTER_IF[$b]}; do
                        [ "${cb#*/}" = 30 ] || continue
                        if [ "$( _net_of "$ca" )" = "$( _net_of "$cb" )" ]; then
                            depth["$b"]=$(( depth[$a] + 1 )); changed=1
                        fi
                    done
                done
            done
        done
    done
    for n in "${T_SEGMENTS[@]}"; do
        T_SEG_HOPS["$n"]="${depth[${T_SEG_ROUTER[$n]}]:-0}"
    done

    # Every router interface a scan could find. The attacker's own default
    # gateway is excluded from the whole of the scoring: it replies to a sweep,
    # so penalising it would punish an accurate scan, and crediting it would
    # reward reading the gateway off the attacker's own routing table.
    for token in "${routers[@]}"; do
        for cidr in ${T_ROUTER_IF[$token]}; do
            ip="${cidr%/*}"
            [ "$ip" = "$T_ATT_GW" ] && continue
            T_ROUTER_IPS+=( "$ip" )
        done
    done
    [ "${#T_ROUTER_IPS[@]}" -gt 0 ] \
        && mapfile -t T_ROUTER_IPS < <( printf '%s\n' "${T_ROUTER_IPS[@]}" | sort -t. -k2,2n -k3,3n -k4,4n )

    # The shape, named from what was actually built rather than from what was
    # drawn, so that a range whose spawn went wrong is described as it stands.
    local nrouters="${#routers[@]}" widest=0 c
    for token in "${routers[@]}"; do
        c=0
        for n in "${T_SEGMENTS[@]}"; do [ "${T_SEG_ROUTER[$n]}" = "$token" ] && c=$(( c + 1 )); done
        [ "$c" -gt "$widest" ] && widest="$c"
    done
    if   [ "$nrouters" -le 1 ] && [ "${#T_SEGMENTS[@]}" -le 1 ]; then T_SHAPE=flat
    elif [ "$nrouters" -le 1 ];                                 then T_SHAPE=fan
    elif [ "$widest" -le 1 ];                                   then T_SHAPE=chain
    else                                                             T_SHAPE=mixed
    fi

    # Open ports, their service, their version and the names a learner may use
    # for them; and the intel each host carries. Both come out of files the
    # profile script wrote only AFTER confirming its service was listening.
    local key
    for token in "${hosts[@]}"; do
        ip="$( docker exec "$( ctn_of "$token" )" ip -brief -4 addr show 2>/dev/null \
               | awk '$1 != "lo" && $2 == "UP" && $3 != "" {sub("/.*","",$3); print $3; exit}' )"
        [ -n "$ip" ] || continue
        T_INTEL["$ip"]=""
        # How the host behaves, read out of its own filter table rather than
        # assumed. Both are things a scan observes, so both belong in the key.
        T_ICMP["$ip"]=replies
        T_SHUT["$ip"]=reset
        T_CLASS["$ip"]=""
        T_FILTERED["$ip"]=""
        while IFS='|' read -r kind f1 f2 f3 f4 f5; do
            case "$kind" in
                P)
                    key="${ip}/${f1}/${f2}"
                    T_PORTS+=( "$key" )
                    T_SERVICE["$key"]="$f3"
                    T_VERSION["$key"]="$f4"
                    T_ACCEPT["$key"]="$f5"
                    ;;
                I)
                    T_INTEL["$ip"]="${T_INTEL[$ip]:+${T_INTEL[$ip]} }$f1"
                    ;;
                B)
                    case "$f1" in
                        icmp-drop) T_ICMP["$ip"]=silent ;;
                        shut-drop) T_SHUT["$ip"]=filtered ;;
                    esac
                    ;;
                C)
                    T_CLASS["$ip"]="$f1"
                    ;;
                F)
                    T_FILTERED["$ip"]="${T_FILTERED[$ip]:+${T_FILTERED[$ip]} }$f1"
                    ;;
            esac
        done < <( docker exec "$( ctn_of "$token" )" sh -c '
            for f in /etc/minilabs/profile.d/*; do
                [ -e "$f" ] || continue
                b=$( basename "$f" ); proto=${b%%-*}; port=${b#*-}
                svc=""; ver=""; acc=""
                while IFS="=" read -r k v; do
                    case "$k" in service) svc=$v ;; version) ver=$v ;; accept) acc=$v ;; esac
                done < "$f"
                echo "P|$proto|$port|$svc|$ver|$acc"
            done
            if [ -s /etc/minilabs/intel ]; then
                while read -r t; do [ -n "$t" ] && echo "I|$t"; done < /etc/minilabs/intel
            fi
            # iptables -S prints the rule as it is stored, not as it was
            # typed: an --icmp-type echo-request written at spawn comes back as
            # "-m icmp --icmp-type 8", so the numeric type is what to match on.
            rules=$( iptables -S INPUT 2>/dev/null )
            case "$rules" in *"--icmp-type 8 -j DROP"*) echo "B|icmp-drop" ;; esac
            case "$rules" in *"-A INPUT -p tcp -j DROP"*) echo "B|shut-drop" ;; esac
            # Per-port drops, which are the ports a scan reports as filtered on
            # a host whose other shut ports come back closed. The rule is matched
            # as a whole line rather than by field position: iptables prints what
            # it stored, so a rule typed as `-p tcp --dport 5900 -j DROP` comes
            # back with a `-m tcp` match module inserted in the middle and every
            # field after `-p` shifts by two.
            echo "$rules" | while read -r line; do
                case "$line" in
                    *" --dport "*" -j DROP") ;;
                    *) continue ;;
                esac
                proto=$( echo "$line" | sed -n "s/.* -p \\([a-z][a-z]*\\) .*/\\1/p" )
                dport=$( echo "$line" | sed -n "s/.*--dport \\([0-9][0-9]*\\) .*/\\1/p" )
                [ -n "$proto" ] && [ -n "$dport" ] && echo "F|${proto}/${dport}"
            done
            [ -f /etc/minilabs/class ] && echo "C|$( cat /etc/minilabs/class )"' 2>/dev/null )
    done

    # The chain's tokens, read off whichever machines are holding them. The loop
    # is over every container in the range rather than over the chain's own list,
    # for the same reason nothing else here opens topology.env: what the learner
    # can submit is what is actually planted, so a step that failed to plant is a
    # milestone nobody is marked down for missing.
    #
    # The file is root-owned and mode 600 inside each container, so `docker exec`
    # reads it and the account the chain logs in as does not.
    local mname mtoken
    for token in "${names[@]}"; do
        case "$token" in netadmin_helper|"$SW") continue ;; esac
        while IFS='|' read -r mname mtoken; do
            [ -n "$mname" ] && [ -n "$mtoken" ] || continue
            T_FLAG_TOKEN["$mname"]="$mtoken"
        done < <( docker exec "$( ctn_of "$token" )" cat "$FLAG_TRUTH_PATH" 2>/dev/null )
    done
}

# The first digit-and-dot run in a string. Both the profile scripts and the
# scorer reduce a version to this, so "lighttpd 1.4.85", "1.4.85" and
# "lighttpd/1.4.85" all become 1.4.85.
truth_version_digits() { echo "$1" | grep -oE '[0-9]+(\.[0-9]+)*' | head -1; }

# True when the submitted version is the truth or a dotted prefix of it, so that
# 1.4 matches a 1.4.85 truth and 1.48 does not.
truth_version_matches() {   # <submitted> <truth>
    local sub; sub="$( truth_version_digits "$1" )"
    local want="$2"
    [ -n "$sub" ] && [ -n "$want" ] || return 1
    case "$want" in "$sub"|"$sub".*) return 0 ;; esac
    return 1
}

# True when the submitted service name is one the port accepts, case-insensitive.
truth_service_matches() {   # <submitted> <accept list>
    local sub want
    sub="$( echo "$1" | tr 'A-Z' 'a-z' )"
    for want in $2; do
        [ "$sub" = "$( echo "$want" | tr 'A-Z' 'a-z' )" ] && return 0
    done
    return 1
}

in_list() {   # in_list <needle> <haystack...>
    local n="$1"; shift
    local x
    for x in "$@"; do [ "$x" = "$n" ] && return 0; done
    return 1
}
