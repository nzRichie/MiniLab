#!/usr/bin/env bash
# Shared definitions for the BGP prefix-hijacking lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS numbers, prefixes, link
# subnets, container names, IPs, interface names, router-ids, and the RPKI
# infrastructure. Every other script sources it; never hardcode any of these in a
# second place. The default_config/*.sh router configs repeat these addresses (they
# run inside the containers, where they cannot source this file) and cite this file
# as the source.
#
# Topology (each AS is one FRR router; each router has one host behind it):
#
#                 AS1  victim, origin of 1.0.0.0/22 (service 1.0.0.1)
#                  |   10.0.12.0/30
#                 AS2  holds legit (direct link to the victim)
#         10.0.23 / \ 10.0.24
#               AS3   AS4     the contested pair
#         10.0.35 \ / 10.0.45
#                 AS5  the attacker's only upstream -> where ROV is enforced
#                  |   10.0.56.0/30
#                 AS6  attacker (real prefix 6.0.0.0/24; impostor at 1.0.0.1)
#
# Single router per AS means eBGP only: no iBGP, no IGP, no route reflectors.
# Every next-hop is a directly-connected /30 link address.
#
# There is deliberately NO local-preference policy anywhere in this lab. Every eBGP
# neighbour carries an empty permit route-map, which satisfies FRR 9.1's
# `bgp ebgp-requires-policy` and leaves best-path selection to plain shortest
# AS-path. A hijack's reach is therefore decided only by prefix length and AS-path
# distance, which is what the lab is about; business relationships and local-pref
# would only obscure it.
#
# AS-path distance is what makes the ladder work. Hop counts from each AS:
#     to AS1 (victim):    AS2=1  AS3=2  AS4=2  AS5=3
#     to AS6 (attacker):  AS2=3  AS3=2  AS4=2  AS5=1
# so at equal prefix length AS5 is the AS the attacker can win, and AS5 is the AS
# that keeps the hijack once both sides have deaggregated to the /24 floor.

LAYER=L3
DC=BGP            # the lab tag; every container name carries _${LAYER}_${DC}_ so
                 # one grep selects the whole lab regardless of AS number.

ASES=(1 2 3 4 5 6)

# ---------------------------------------------------------------------------
# The hijack target. AS1 holds 1.0.0.0/22 and serves 1.0.0.1. Both sides walk a
# deaggregation ladder down to /24 and no further: /24 is the longest prefix the
# global routing table accepts, so it is the floor for both attacker and victim.
# That floor is the point of Part 2 -- past it, deaggregation stops helping and
# only origin validation settles who owns the block.
VICTIM_AS=1
VICTIM_PREFIX="1.0.0.0/22"     # AS1's allocation, the aggregate it announces first
VICTIM_SVC_IP="1.0.0.1"        # the service every vantage curls

# The victim's deaggregation stages (Part 2). Announced IN ADDITION to nothing --
# each stage replaces the previous announcement set.
VICTIM_DEAGG_23=("1.0.0.0/23" "1.0.2.0/23")
VICTIM_DEAGG_24=("1.0.0.0/24" "1.0.1.0/24" "1.0.2.0/24" "1.0.3.0/24")

# The attacker's ladder (Part 1). Same floor: it cannot go below /24 either.
ATTACKER_AS=6
HIJACK_EQUAL="1.0.0.0/22"                       # stage 1: equal-length MOAS hijack
HIJACK_SUB23="1.0.0.0/23"                       # stage 2: one level more specific
HIJACK_SUB24=("1.0.0.0/24" "1.0.1.0/24")        # stage 3: at the floor
ATTACKER_UPSTREAM_AS=5         # the attacker's only upstream; where ROV is enforced
ATTACKER_LINK_IP="10.0.56.2"   # AS6's address on the AS5<->AS6 link

# ---------------------------------------------------------------------------
# Per-AS host subnet and the host on it.
#   role   : the container-name suffix and the shell.sh selector
#   host_ip: the host's address on its uplink to the router
#   gw     : the router's host-facing address (the host's default gateway)
declare -A AS_PREFIX AS_ROLE AS_HOST_IP AS_GW AS_ROUTERID
for as in "${ASES[@]}"; do
    AS_PREFIX[$as]="${as}.0.0.0/24"
    AS_GW[$as]="${as}.0.0.254"
    AS_ROUTERID[$as]="${as}.${as}.${as}.${as}"
    AS_ROLE[$as]="client"
    AS_HOST_IP[$as]="${as}.0.0.100"
done
# AS1 holds a /22, not a /24, and hosts the victim service on the first /24 of it.
# AS6 hosts the attacker and its impostor.
AS_PREFIX[1]="$VICTIM_PREFIX"
AS_ROLE[1]="victim";   AS_HOST_IP[1]="1.0.0.1"
AS_ROLE[6]="attacker"; AS_HOST_IP[6]="6.0.0.100"

# AS6 impostor slice: the attacker stands up a /25 of the victim's block locally, so
# that once it announces any of the hijack prefixes it FORWARDS the drawn traffic to
# the impostor host rather than black-holing it. The /25 is connected, so it is more
# specific than every prefix either side announces and always wins inside AS6.
IMPOSTOR_SUBNET="1.0.0.0/25"
IMPOSTOR_HOST_IP="1.0.0.1"     # the attacker host's impersonating address
IMPOSTOR_GW="1.0.0.126"        # AS6 router's secondary on the host link

# The identity banners each host serves on port 80. A captured client's curl to the
# service IP reads back whichever of these is answering, so a hijack shows up as the
# banner flipping. Defined once here; spawn/reset start the servers with them and
# status/selftest assert against them.
VICTIM_BANNER="AS1: legitimate"
ATTACKER_BANNER="AS6: HIJACKED (impostor)"

# ---------------------------------------------------------------------------
# Inter-AS links, eBGP over a /30. Fields: "<a> <b> <a_ip> <b_ip> <subnet>",
# with a<b; a takes .1, b takes .2. Router a's interface to b is named to_as<b>.
LINKS=(
    "1 2 10.0.12.1 10.0.12.2 10.0.12.0/30"
    "2 3 10.0.23.1 10.0.23.2 10.0.23.0/30"
    "2 4 10.0.24.1 10.0.24.2 10.0.24.0/30"
    "3 5 10.0.35.1 10.0.35.2 10.0.35.0/30"
    "4 5 10.0.45.1 10.0.45.2 10.0.45.0/30"
    "5 6 10.0.56.1 10.0.56.2 10.0.56.0/30"
)

# ---------------------------------------------------------------------------
# RPKI infrastructure. Two containers outside the BGP topology:
#
#   rir        Krill, in testbed mode. It is both the trust anchor and the CA
#              portal: it issues each AS a resource certificate for the block that
#              AS holds, and it is where a ROA is created. Reachable in a browser
#              on the host at https://127.0.0.1:3000 and by krillc inside it.
#   validator  Routinator, the Relying Party cache. It fetches Krill's repository
#              over RRDP, validates every object cryptographically, and serves the
#              resulting VRPs to routers over RTR on port 3323.
#
# They talk to each other on a private docker bridge (the only place in this lab
# that is not veth-wired, because publishing Krill's web UI to the host needs a
# bridge). The routers stay --network=none: the validator reaches each ROV router
# over its own point-to-point veth, so no router is ever attached to a docker
# network and the BGP topology keeps no route off the host.
RIR_CTN="0_${LAYER}_${DC}_rir"
VALIDATOR_CTN="0_${LAYER}_${DC}_validator"
RPKI_NET="minilabs-rpki-${DC,,}"          # private docker bridge, created by spawn
RPKI_NET_SUBNET="172.28.0.0/24"
RIR_NET_IP="172.28.0.10"
VALIDATOR_NET_IP="172.28.0.11"

# Krill 0.16 rejects bare IP addresses in its service URIs ("MUST use hostnames in
# URIs for certificate requests"), so the RIR is addressed by name everywhere and
# every container that talks to it gets an --add-host entry for this name.
RIR_FQDN="rir.minilabs"
RIR_PORT=3000
KRILL_TOKEN="minilabs-rpki-token"         # Krill admin token: the web UI password
                                          # and the krillc credential.
KRILL_UI_URL="https://127.0.0.1:${RIR_PORT}"

# Routers that run Route Origin Validation. Each gets a point-to-point veth to the
# validator and speaks RTR to it. AS3 is a bystander that only VALIDATES (so the
# learner can see Invalid routes that are still being used); AS5 is the attacker's
# upstream and is where the learner applies the policy that acts on the verdict.
RPKI_CACHE_ASES=(3 5)
ROV_ENFORCE_AS=5
RTR_PORT=3323
# Point-to-point links validator <-> router: "<as> <validator_ip> <router_ip> <subnet>"
RPKI_LINKS=(
    "3 172.28.3.1 172.28.3.2 172.28.3.0/30"
    "5 172.28.5.1 172.28.5.2 172.28.5.0/30"
)
rpki_if_router()    { echo "to_rpki"; }        # router side of the validator link
rpki_if_validator() { echo "to_as${1}"; }      # validator side, toward AS <1>

# The ROAs Krill is preloaded with at spawn, as "<ca> <prefix> <asn>". AS6 arrives
# as a responsible operator that has already registered its own block, so the
# learner sees a Valid route on day one and has all three RPKI states on screen.
# AS1 deliberately arrives with a CA and NO ROA: registering it is the learner's job.
PRELOADED_ROAS=(
    "AS6 6.0.0.0/24 6"
)
# The CAs Krill creates at spawn, as "<ca> <ipv4 resources> <asn>". A CA can only
# sign a ROA for resources on its certificate, which is what makes the hijack
# unsignable: AS6 holds 6.0.0.0/24 and nothing inside 1.0.0.0/22.
KRILL_CAS=(
    "AS1 1.0.0.0/22 1"
    "AS6 6.0.0.0/24 6"
)
# The ROA the learner is meant to end up with. maxLength 24 is load-bearing: without
# it the victim's own deaggregated /23s and /24s become RPKI-Invalid.
VICTIM_ROA_NOMAXLEN="${VICTIM_PREFIX} => ${VICTIM_AS}"
VICTIM_ROA_CORRECT="${VICTIM_PREFIX}-24 => ${VICTIM_AS}"

# ---------------------------------------------------------------------------
# Container names follow the platform convention <AS>_<LAYER>_<DC>_<role>. The
# router of each AS is <AS>_L3_BGP_router; the host is <AS>_L3_BGP_<role>. The two
# RPKI containers carry AS 0, the same infrastructure slot the wiring helper uses.
router_ctn() { echo "${1}_${LAYER}_${DC}_router"; }
host_ctn()   { echo "${1}_${LAYER}_${DC}_${AS_ROLE[$1]}"; }

# Interface names (renamed after the veth is moved into the container namespace).
peer_if()  { echo "to_as${1}"; }   # a router's interface toward AS <1>
HOST_IF_ROUTER="host"              # router side of the host link
HOST_IF_HOST="uplink"              # host side of the host link

# Every lab container matches this; teardown/status select on it alone.
LAB_FILTER="_${LAYER}_${DC}_"

# ---------------------------------------------------------------------------
SWITCH_IMAGE=""                    # this lab has no switch: all links are L3 point-to-point
ROUTER_IMAGE="d_router_bgp"
HOST_IMAGE="d_host_bgp"
RIR_IMAGE="d_rir_krill"
VALIDATOR_IMAGE="d_validator_routinator"

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# ---------------------------------------------------------------------------
# Image preflight, called by spawn.sh before the first `docker run`. Docker caches
# them, so every spawn after the first is a no-op here. The router and host images
# are built FROM the published miniinterneteth/d_host base; the RIR and validator
# are built FROM the upstream NLnet Labs images, which is why the first spawn on a
# machine needs network access.
ensure_images() {
    local img dir
    for pair in "$ROUTER_IMAGE:router" "$HOST_IMAGE:host" "$RIR_IMAGE:rir" "$VALIDATOR_IMAGE:validator"; do
        img="${pair%%:*}"; dir="${pair##*:}"
        if ! docker image inspect "$img" >/dev/null 2>&1; then
            echo "[spawn] building $img from image/${dir} (first run only)"
            docker build -t "$img" "$LAB_DIR/image/${dir}" \
                || { echo "failed to build $img" >&2; return 1; }
        fi
    done
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
# created in never matters. Asking for the host's namespace (--network=host)
# only breaks the helper under a rootless daemon, where that namespace belongs to
# a user namespace the helper holds no privilege in and every `ip link add`
# returns EPERM. --pid=host stays: it is what makes each lab container's
# /proc/<pid>/ns/net reachable for the moves.
#
# Renames run through `nsenter --net`, not `ip netns exec`. iproute2 remounts
# /sys on every namespace switch and a user namespace forbids that, while the
# rename itself is pure netlink and needs no sysfs at all.
#
# The kernel objects are identical to the host-root path: same veth pair, same
# namespaces, same interface names, same OVS ports. Only the identity of the
# process issuing the netlink calls changes, which nothing in the data plane can
# observe. Docker access is the only privilege a learner needs, and on a rootless
# daemon that access no longer carries root on the host.
HELPER_CTN="0_${LAYER}_${DC}_netadmin"

helper_start() {
    docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true
    docker run -d --rm --name "$HELPER_CTN" \
        --privileged --network=none --pid=host \
        "$HOST_IMAGE" sleep 600 >/dev/null
    for _ in $(seq 1 40); do
        if docker exec "$HELPER_CTN" true >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    echo "helper container $HELPER_CTN did not become ready" >&2
    return 1
}
helper()            { docker exec "$HELPER_CTN" "$@"; }
helper_stop()       { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }

# Address an interface from the helper rather than from inside the target
# container. The RPKI containers are upstream images with no iproute2 of their own,
# so their veth end is configured through the helper's netns handle instead.
helper_addr() {   # <pid> <ifname> <cidr>
    helper nsenter --net="/proc/$1/ns/net" ip address replace "$3" dev "$2"
    helper nsenter --net="/proc/$1/ns/net" ip link set dev "$2" up
}

# ---------------------------------------------------------------------------
# Wait until a router's FRR/vtysh is answering (spawn calls this before applying
# config, and after starting FRR). Bounded so a broken image fails loudly.
wait_for_vtysh() {
    local ctn="$1"
    for _ in $(seq 1 60); do
        if docker exec "$ctn" vtysh -c 'show version' >/dev/null 2>&1; then return 0; fi
        sleep 0.5
    done
    echo "vtysh never came up in $ctn" >&2
    return 1
}

# The best-path oracle: the origin AS of the current best route to a prefix, read
# from one router. Returns the last AS in the AS-path (the origin), or "local" if
# the router itself originates it, or empty if it has no route. The JSON parse runs
# INSIDE the router container (python3 ships there with frr-pythontools), so the
# host needs no python. Used by status.sh and selftest.sh to tell whose prefix won.
best_path_origin() {
    local ctn="$1" prefix="$2"
    docker exec "$ctn" sh -c "vtysh -c 'show ip bgp ${prefix} json' 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in d.get(\"paths\",[]):
    bp=p.get(\"bestpath\")
    if (isinstance(bp,dict) and bp.get(\"overall\")) or p.get(\"best\"):
        asp=p.get(\"aspath\",{}).get(\"string\",\"\").split()
        print(asp[-1] if asp else \"local\")
        break
'"
}

# The RPKI oracle: the validation state FRR has assigned to the best path for a
# prefix -- valid, invalid, notfound, or empty when the router has no route. Only
# meaningful on a router that has an rpki cache configured; a router with no cache
# reports everything as notfound.
rpki_state() {
    local ctn="$1" prefix="$2"
    docker exec "$ctn" sh -c "vtysh -c 'show ip bgp ${prefix} json' 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in d.get(\"paths\",[]):
    bp=p.get(\"bestpath\")
    if (isinstance(bp,dict) and bp.get(\"overall\")) or p.get(\"best\"):
        print(str(p.get(\"rpkiValidationState\",\"\")).lower())
        break
'"
}

# ---------------------------------------------------------------------------
# krillc inside the RIR container. The container carries KRILL_CLI_SERVER and
# KRILL_CLI_TOKEN in its environment (docker exec inherits them), so this is the
# same bare command the handout has the learner type.
krillc() { docker exec "$RIR_CTN" krillc "$@"; }

# A Krill CA can only sign a ROA for resources its certificate carries, and that
# certificate arrives asynchronously from the testbed trust anchor. `krillc parents
# statuses` reports success BEFORE the certificate is installed, so polling that
# leads to "prefixes not on any of your certificates" when the ROA is added. The
# state that actually means ready is the resource class going active.
krill_ca_ready() {
    local ca="$1" i
    for i in $(seq 1 60); do
        if krillc show --ca "$ca" 2>/dev/null | grep -q "State: active"; then return 0; fi
        krillc bulk refresh >/dev/null 2>&1 || true
        krillc bulk sync    >/dev/null 2>&1 || true
        sleep 2
    done
    echo "krill CA ${ca} never became active" >&2
    return 1
}

# How many VRPs the validator is currently serving. Reads Routinator's HTTP API
# from inside the validator container, so the host needs no tooling.
vrp_count() {
    docker exec "$VALIDATOR_CTN" sh -c \
        "wget -q -O - http://127.0.0.1:9556/csv 2>/dev/null | tail -n +2 | grep -c ." 2>/dev/null || echo 0
}
