#!/usr/bin/env bash
# Spawn the scanning practice range.
#
#   scripts/spawn.sh <easy|normal|hard> [seed]
#
# Draws a range from the seed (generate.sh), then creates only this range's
# containers and wires only its links, driving docker and the veth/OVS primitives
# directly. It deliberately does NOT call platform/startup.sh, which brings up
# the entire course network; that is the server-scale path this project exists to
# avoid.
#
# The seed is printed as the first line of output, and it is printed again by
# status.sh and on every line score.sh prints, so a (tier, seed) pair reproduces
# a range exactly. A tutor can set one seed for a whole class and compare scores
# against each other, and a range that generates badly is pinned in a bug report
# rather than described.
#
# What is wired:
#   * one bridge per segment, all of them on ONE switch container. Bridges in one
#     OVS instance do not forward between each other, so N segments cost N
#     bridges and no extra container.
#   * one point-to-point veth per router-to-router link, the same primitive the
#     attacker's own segment would use, so depth costs one container per router
#     and no bridge at all.
#   * a dead range is wired exactly like a live segment, bridge and router
#     interface and all. The only difference is that no host is plugged into it,
#     which is what makes a sweep of it cost time and return ICMP unreachables.
#
# The privileged part of the wiring goes through a helper container, never
# through bare `ip` on the host, so docker access is the only privilege needed.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

tier="${1:-}"
seed="${2:-}"
case "$tier" in
    easy|normal|hard) ;;
    *) echo "usage: $( basename "$0" ) <easy|normal|hard> [seed]" >&2; exit 2 ;;
esac

# Open vSwitch is NOT required on the host: every ovs-vsctl call runs inside the
# switch container, whose image ships OVS. Docker reachability is the real
# prerequisite, and it covers an unreachable daemon as well as a stopped one.
command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and can this account reach it? (try: docker info)" >&2
    exit 1
}

# Captured and matched rather than piped into `grep -q`: this script runs with
# `set -o pipefail`, under which a matching `grep -q` closes the pipe, `docker
# ps` dies on SIGPIPE, and the pipeline's status stops meaning what it says.
existing="$( docker ps -a --format '{{.Names}}' )"
if [[ $'\n'"$existing"$'\n' == *$'\n'"$SW_CTN"$'\n'* ]]; then
    echo "A range is already spawned ($SW_CTN exists). Run Teardown first, or Regenerate." >&2
    exit 1
fi

# 1. Draw the range. generate.sh touches no containers and writes one file.
"$( dirname "${BASH_SOURCE[0]}" )/generate.sh" "$tier" "$seed"
load_topology

ensure_images

# ---------------------------------------------------------------------------
# 2. Containers. No data-plane network: the veth links and the OVS bridges are
#    the only fabric.

log "starting switch $SW_CTN"
docker run -d --name "$SW_CTN" --network=none \
    --cap-add=ALL --cap-drop=SYS_RESOURCE --hostname "$SW" \
    "$SWITCH_IMAGE" sh -c "$SWITCH_CMD" >/dev/null

# Every container is given an explicit command, which is what stops the base
# image's default CMD (`sshd -D -e`) from running. Left alone it would open port
# 22 on every container in the range, so every host would answer the same way and
# the survey would report an SSH service the seed never drew there, including on
# the one host whose whole purpose is to have nothing listening.
IDLE_CMD=(sleep infinity)

# ip_forward is set at creation rather than written at runtime: Docker mounts
# /proc/sys read-only in an unprivileged container, and making a router
# privileged to write one sysctl is more privilege than this range needs.
for r in "${ROUTERS[@]}"; do
    log "starting router $( ctn_of "$r" )"
    docker run -d --name "$( ctn_of "$r" )" --network=none \
        --cap-add=NET_ADMIN --sysctl net.ipv4.ip_forward=1 --hostname "$r" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

# The initial TTL is one of the four signals a host's class is inferred from, and
# it is set HERE rather than written later because net.ipv4.ip_default_ttl is one
# of the sysctls Docker will not let a container write: /proc/sys is mounted
# read-only in an unprivileged container, so a `docker exec sysctl -w` reports an
# error, or on some kernels silently does nothing, and every host would answer
# with 64 whatever class it was drawn as. The mac-flooding lab lost time to the
# same trap.
for h in "${HOSTS[@]}"; do
    log "starting host $( ctn_of "$h" ) (${TARGET_CLASS[$h]})"
    docker run -d --name "$( ctn_of "$h" )" --network=none \
        --cap-add=NET_ADMIN --hostname "${TARGET_HOSTNAME[$h]}" \
        --sysctl "net.ipv4.ip_default_ttl=${CLASS_TTL[${TARGET_CLASS[$h]}]}" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
done

log "starting attacker $ATTACKER_CTN"
docker run -d --name "$ATTACKER_CTN" --network=none \
    --cap-add=NET_ADMIN --hostname attacker \
    "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null

# The vault, on ranges three layers deep and more. It is not one of the drawn
# hosts and it is not scored as one: the survey half of the range is worth
# exactly what it was worth before, and this is territory the chain opens.
if [ -n "$VAULT_NET" ]; then
    log "starting vault $VAULT_CTN"
    docker run -d --name "$VAULT_CTN" --network=none \
        --cap-add=NET_ADMIN --hostname "$VAULT" \
        "$HOST_IMAGE" "${IDLE_CMD[@]}" >/dev/null
fi

# ---------------------------------------------------------------------------
# 3. One bridge per segment and per dead range, all on the one switch container.
#    Single switch, no loops, so STP stays OFF: it would hold ports in
#    listening/learning for 15 to 30 seconds and delay the first packet.

log "waiting for Open vSwitch in $SW_CTN"
for _ in $(seq 1 40); do
    docker exec "$SW_CTN" ovs-vsctl show >/dev/null 2>&1 && break
    sleep 0.5
done

bridges=()
for s in "${SEGMENTS[@]}";    do bridges+=( "${SEG_BRIDGE[$s]}" ); done
for d in "${DEAD_RANGES[@]}"; do bridges+=( "${DEAD_BRIDGE[$d]}" ); done
[ -n "$VAULT_NET" ] && bridges+=( "$VAULT_BRIDGE" )
for br in "${bridges[@]}"; do
    log "creating bridge $br"
    docker exec "$SW_CTN" ovs-vsctl \
        -- add-br "$br" \
        -- set bridge "$br" stp_enable=false \
        -- set-fail-mode "$br" standalone >/dev/null
done

# ---------------------------------------------------------------------------
# 4. The wiring, from a privileged helper container. helper_stop is trapped so
#    the helper goes away however this script exits.
helper_start
trap helper_stop EXIT

i=0

plug() {   # put one end of a fresh veth into a container and rename it there
    local ctn="$1" want_if="$2" tmp="$3" pid
    pid="$(docker inspect -f '{{.State.Pid}}' "$ctn")"
    helper ip link set "$tmp" netns "$pid"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$tmp" name "$want_if"
    helper nsenter --net="/proc/$pid/ns/net" ip link set dev "$want_if" up
}

wire_to_bridge() {   # <ctn> <ifname in ctn> <switch port name> <bridge>
    local ctn="$1" host_if="$2" sw_port="$3" br="$4" spid
    i=$(( i + 1 ))
    local ta="vb${i}a" tb="vb${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$ctn" "$host_if" "$ta"
    spid="$(docker inspect -f '{{.State.Pid}}' "$SW_CTN")"
    helper ip link set "$tb" netns "$spid"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$tb" name "$sw_port"
    helper nsenter --net="/proc/$spid/ns/net" ip link set dev "$sw_port" up
    docker exec "$SW_CTN" ovs-vsctl add-port "$br" "$sw_port" >/dev/null
}

wire_point_to_point() {   # <ctnA> <ifA> <ctnB> <ifB>
    i=$(( i + 1 ))
    local ta="vp${i}a" tb="vp${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$1" "$2" "$ta"
    plug "$3" "$4" "$tb"
}

# 4a. Every segment: its router's interface, then each host on it. The attacker's
#     own segment is a bridge like any other, which is what lets a host sit on it
#     at every shape but flat.
for s in "${SEGMENTS[@]}"; do
    r="${SEG_ROUTER[$s]}"
    log "wiring $s (${SEG_SUBNET[$s]}) on ${SEG_BRIDGE[$s]}: $r"
    wire_to_bridge "$( ctn_of "$r" )" "${AS}-${s}" "$( sw_port_of "${r}-${s}" )" "${SEG_BRIDGE[$s]}"
    for h in ${SEG_HOSTS[$s]}; do
        wire_to_bridge "$( ctn_of "$h" )" "$HOST_IF" "$( sw_port_of "$h" )" "${SEG_BRIDGE[$s]}"
    done
done
log "wiring attacker onto ${SEG_LOCAL} (${ATT_SUBNET})"
wire_to_bridge "$ATTACKER_CTN" "$ATT_IF" "$( sw_port_of attacker )" "${SEG_BRIDGE[$SEG_LOCAL]}"

# 4b. Dead ranges: the router's interface and nothing else on the bridge. A probe
#     into one reaches the router, which resolves the address on a segment where
#     nothing will answer, and gives up.
for d in "${DEAD_RANGES[@]}"; do
    r="${DEAD_ROUTER[$d]}"
    log "wiring $d (${DEAD_SUBNET[$d]}, routed and empty) on ${DEAD_BRIDGE[$d]}: $r"
    wire_to_bridge "$( ctn_of "$r" )" "${AS}-${d}" "$( sw_port_of "${r}-${d}" )" "${DEAD_BRIDGE[$d]}"
done

# 4b2. The vault segment: the deepest router's interface, and the vault itself.
if [ -n "$VAULT_NET" ]; then
    log "wiring $VAULT ($VAULT_NET) on $VAULT_BRIDGE: $VAULT_ROUTER"
    wire_to_bridge "$( ctn_of "$VAULT_ROUTER" )" "${AS}-${VAULT}" \
        "$( sw_port_of "${VAULT_ROUTER}-${VAULT}" )" "$VAULT_BRIDGE"
    wire_to_bridge "$VAULT_CTN" "$HOST_IF" "$( sw_port_of "$VAULT" )" "$VAULT_BRIDGE"
fi

# 4c. Router-to-router links.
for t in "${TRANSITS[@]}"; do
    a="${TRANSIT_A[$t]}"; b="${TRANSIT_B[$t]}"
    log "wiring transit $t (${TRANSIT_SUBNET[$t]}): $a <-> $b"
    wire_point_to_point "$( ctn_of "$a" )" "${AS}-${b}" "$( ctn_of "$b" )" "${AS}-${a}"
done

# ---------------------------------------------------------------------------
# 5. Addressing and routing, written from state/topology.env.
#
# The addresses are applied here rather than by a per-device starter script,
# because on a range there is no fixed device to write a starter script for:
# every address is drawn. generate.sh is still the only thing that DERIVES an
# address; this reads them back and applies them.

for r in "${ROUTERS[@]}"; do
    ctn="$( ctn_of "$r" )"
    for spec in ${ROUTER_IFACES[$r]}; do
        ifname="${spec%%:*}"; cidr="${spec#*:}"
        docker exec "$ctn" ip address replace "$cidr" dev "$ifname"
        docker exec "$ctn" ip link set "$ifname" up
    done
    for route in ${ROUTER_ROUTES[$r]}; do
        dst="${route%%>*}"; via="${route#*>}"
        docker exec "$ctn" ip route replace "$dst" via "$via"
    done
    log "$( ctn_of "$r" ) addressed and routed"
done

docker exec "$ATTACKER_CTN" ip address replace "${ATTACKER_IP}/24" dev "$ATT_IF"
docker exec "$ATTACKER_CTN" ip link set "$ATT_IF" up
docker exec "$ATTACKER_CTN" ip route replace default via "$ATT_GW"
docker exec "$ATTACKER_CTN" mkdir -p /root/scan /etc/minilabs
docker exec "$ATTACKER_CTN" touch "$FINDINGS_PATH"

# What the exercise is, written where score.sh can read it back off the running
# range. score.sh derives every ground-truth fact from the live containers and
# opens no file under state/ but the findings copy and the attempt log, so the
# seed, the tier, what the learner was told, and the clock the elapsed time is
# measured against all have to live in a container too. The timestamp is kept out
# of topology.env for a second reason: that file must be byte-identical for a
# given (tier, seed) pair, which a file holding a clock reading never could be.
{
    kv RANGE_SEED       "${RANGE_SEED}"
    kv RANGE_TIER       "${RANGE_TIER}"
    kv RANGE_MUTATOR    "${RANGE_MUTATOR}"
    kv RANGE_ORG_NAME   "${RANGE_ORG_NAME}"
    kv RANGE_OPENING    "${RANGE_OPENING}"
    kv RANGE_GIVEN      "${RANGE_GIVEN}"
    kv RANGE_GIVEN_NETS "${RANGE_GIVEN_NETS}"
    kv RANGE_DEPTH      "${RANGE_DEPTH}"
    kv RANGE_VAULT_NET  "${VAULT_NET}"
    kv RANGE_SPAWNED_AT "$( date +%s )"
} | docker exec -i "$ATTACKER_CTN" sh -c "cat > /etc/minilabs/range.env"

# zmap builds raw Ethernet frames, so it needs the gateway's hardware address
# before it can send anything. Left to work it out itself on this link it hangs
# indefinitely after logging "found gateway IP", and it does so even when the
# kernel's own neighbour entry for the gateway is present and REACHABLE. Passing
# -G on the command line fixes it, but that would put an argument in every zmap
# command in the field manual that exists only to work around the range's own
# plumbing. Writing the same two values into zmap's config file instead lets the
# manual run zmap the way its documentation says to.
docker exec "$ATTACKER_CTN" ping -c 1 -W 2 "$ATT_GW" >/dev/null 2>&1 || true
gw_mac="$( docker exec "$ATTACKER_CTN" ip neigh show "$ATT_GW" | awk '{print $5}' | head -1 )"
if [ -n "$gw_mac" ]; then
    docker exec "$ATTACKER_CTN" sh -c \
        "sed -i '/^interface /d;/^gateway-mac /d' /etc/zmap/zmap.conf; \
         printf 'interface \"%s\"\ngateway-mac \"%s\"\n' '$ATT_IF' '$gw_mac' >> /etc/zmap/zmap.conf"
else
    log "WARNING: could not learn the gateway MAC; zmap will need -G"
fi

for h in "${HOSTS[@]}"; do
    ctn="$( ctn_of "$h" )"
    seg="${TARGET_SEG[$h]}"
    # The vendor half of the MAC address, which is the second of the four signals
    # a class is inferred from and the only one that is readable without sending
    # the host anything: an ARP scan on the local segment collects it. The
    # interface has to be down to be renumbered, and the last three octets are
    # derived from the host's own address so that two machines on one segment
    # never present the same hardware address.
    oui="${CLASS_OUI[${TARGET_CLASS[$h]}]}"
    IFS=. read -r _o1 _o2 _o3 _o4 <<< "${TARGET_IP[$h]}"
    mac="$( printf '%s:%02x:%02x:%02x' "$oui" "$_o2" "$_o3" "$_o4" )"
    docker exec "$ctn" ip link set "$HOST_IF" down
    docker exec "$ctn" ip link set "$HOST_IF" address "$mac"
    docker exec "$ctn" ip address replace "${TARGET_IP[$h]}/24" dev "$HOST_IF"
    docker exec "$ctn" ip link set "$HOST_IF" up
    docker exec "$ctn" ip route replace default via "${SEG_GW[$seg]}"

    # The ghost interface: administratively down, holding an address in a block
    # that is routed nowhere, and visible in this machine's SNMP address table
    # exactly as a live interface is. It is a veth pair rather than a dummy
    # device because veth is already loaded on any host that can run this range
    # and the dummy module may not be, and because only one end of it is ever
    # brought anywhere near a bridge: neither end is, so it carries no traffic.
    ghost=""
    for kv in ${TARGET_PARAM[$h]}; do
        case "$kv" in ghost_net=*) ghost="${kv#*=}" ;; esac
    done
    if [ -n "$ghost" ]; then
        docker exec "$ctn" ip link add "${AS}-ghost" type veth peer name "${AS}-ghostp" 2>/dev/null || true
        docker exec "$ctn" ip address replace "${ghost%.0/24}.1/24" dev "${AS}-ghost"
        docker exec "$ctn" ip link set "${AS}-ghost" down
        log "$ctn: ghost interface holding ${ghost}, administratively down"
    fi
done

if [ -n "$VAULT_NET" ]; then
    docker exec "$VAULT_CTN" ip address replace "${VAULT_IP}/24" dev "$HOST_IF"
    docker exec "$VAULT_CTN" ip link set "$HOST_IF" up
    docker exec "$VAULT_CTN" ip route replace default via "$VAULT_GW"

    # The filter in front of the vault. It is a FORWARD rule on the vault's own
    # router rather than a missing route, and the difference is what the learner
    # sees: a missing route answers with a network-unreachable from whichever
    # router ran out of table, which says the subnet does not exist, while this
    # answers with an administratively-prohibited from the router that serves it,
    # which says the subnet exists and something decided not to let this packet
    # through. The second is a door worth going and looking for; the first is
    # indistinguishable from empty space.
    #
    # Claiming this subnet is neither credited nor penalised, so following the
    # breadcrumb cannot cost a learner marks for being right about it.
    vr="$( ctn_of "$VAULT_ROUTER" )"
    from_ip="${TARGET_IP[$CHAIN_VAULT_FROM]}"
    docker exec "$vr" iptables -F FORWARD
    docker exec "$vr" iptables -A FORWARD -s "$from_ip" -d "$VAULT_NET" -j ACCEPT
    docker exec "$vr" iptables -A FORWARD -s "$VAULT_NET" -j ACCEPT
    docker exec "$vr" iptables -A FORWARD -d "$VAULT_NET" \
        -j REJECT --reject-with icmp-admin-prohibited
    log "$vr: only $from_ip may reach $VAULT_NET"
fi

# A routed-and-empty subnet that answers an administrative rejection rather than
# a host unreachable, on a `segmented` range. The two answers are different
# facts: a host unreachable says the router tried to resolve an address on that
# segment and nothing answered, an administratively-prohibited says the router
# did not try. Both mean "no host here for you", and only one of them means the
# subnet is empty.
for d in "${DEAD_RANGES[@]}"; do
    [ "${DEAD_ANSWER[$d]:-unreachable}" = prohibited ] || continue
    dr="$( ctn_of "${DEAD_ROUTER[$d]}" )"
    docker exec "$dr" iptables -A FORWARD -d "${DEAD_SUBNET[$d]}" \
        -j REJECT --reject-with icmp-admin-prohibited
    log "$dr: ${DEAD_SUBNET[$d]} answers administratively prohibited"
done

# The router that does not send ICMP time-exceeded. A traceroute through it shows
# a gap where a hop should be, and the distance past it has to be counted rather
# than read off the numbering. r1 is never the one, because a gap at the first
# hop is a range where traceroute does not work at all.
if [ -n "${RANGE_NO_TTL_ROUTER:-}" ]; then
    nr="$( ctn_of "$RANGE_NO_TTL_ROUTER" )"
    docker exec "$nr" iptables -A OUTPUT -p icmp --icmp-type time-exceeded -j DROP
    log "$nr: sends no ICMP time-exceeded"
fi

# ---------------------------------------------------------------------------
# 6. Per-host behaviour: whether an echo request is answered, and whether a port
#    with nothing behind it sends a reset or nothing at all.
#
# Both are applied with iptables inside each container's own network namespace,
# so they need NET_ADMIN and nothing more. The rules are what turn a host list
# into a discovery exercise: a host that drops echo requests is missed by a ping
# sweep and found by a TCP probe, and a host that drops shut ports reports
# `filtered` where its neighbour reports `closed`.
for h in "${HOSTS[@]}"; do
    ctn="$( ctn_of "$h" )"
    docker exec "$ctn" iptables -F INPUT
    if [ "${TARGET_ICMP[$h]}" = drop ]; then
        # Echo and timestamp are the two ICMP probes a host-discovery sweep uses,
        # so both are dropped; nothing short of a transport-layer probe reveals
        # this host.
        docker exec "$ctn" iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
        docker exec "$ctn" iptables -A INPUT -p icmp --icmp-type timestamp-request -j DROP
    fi
    if [ "${TARGET_SHUT[$h]}" = drop ]; then
        docker exec "$ctn" iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        for spec in ${TARGET_PORTS[$h]}; do
            proto="${spec%%/*}"; port="${spec#*/}"
            docker exec "$ctn" iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
        done
        # An FTP service also needs its passive data range open, because the
        # client opens a second connection to a port the server names and that
        # connection is inbound like any other. Without this the share accepts a
        # login and every listing and every retrieval hangs, so the finding that
        # depends on reading a file off it becomes unobtainable on exactly the
        # seeds where this host also drew the filtered behaviour.
        if [ "${TARGET_PROFILE[$h]}" = ftp ]; then
            docker exec "$ctn" iptables -A INPUT -p tcp \
                --dport "${FTP_PASV_MIN}:${FTP_PASV_MAX}" -j ACCEPT
        fi
        # Everything else is dropped rather than refused, so a scanner cannot
        # tell a shut port from a filtered one and reports `filtered`.
        docker exec "$ctn" iptables -A INPUT -p tcp -j DROP
        docker exec "$ctn" iptables -A INPUT -p udp -j DROP
    fi
    # Per-port state, on a host that refuses everything else. These few named
    # ports are dropped, so one machine reports open, closed and filtered at
    # once. A host-wide setting could never produce that, and the three-state
    # table the field manual teaches is only readable on a host that shows all
    # three. The rules go in FIRST, ahead of any accept, because iptables takes
    # the first matching rule and a later DROP would never be reached.
    if [ -n "${TARGET_FILTERED[$h]}" ]; then
        for spec in ${TARGET_FILTERED[$h]}; do
            proto="${spec%%/*}"; port="${spec#*/}"
            docker exec "$ctn" iptables -I INPUT 1 -p "$proto" --dport "$port" -j DROP
        done
        log "$ctn: ${TARGET_FILTERED[$h]} filtered rather than refused"
    fi
done

# ---------------------------------------------------------------------------
# 7. The services. Each host gets the whole profiles/ directory (they source a
#    shared helper) plus the parameters the seed drew for it, and then the one
#    profile script it drew is run.

# The zone data the DNS profile builds its zone from: every live segment's
# gateway and every host in the range. It is written from topology.env so the
# zone cannot disagree with the network it describes, and it names addresses
# only, so a transfer hands over the map and not the survey.
zone_data="$STATE_DIR/zone.data"
{
    for s in "${SEGMENTS[@]}"; do
        printf 'gw-%s\t%s\n' "$s" "${SEG_GW[$s]}"
    done
    for h in "${HOSTS[@]}"; do
        printf '%s\t%s\n' "${TARGET_HOSTNAME[$h]}" "${TARGET_IP[$h]}"
    done
    printf 'ns\t%s\n' "$ATT_GW"
    # Stale records: names for addresses that hold nothing. A zone is a records
    # file and not a host list, and a transfer hands over what somebody wrote in
    # it rather than what is running. Reporting one of these as a host without
    # probing it costs a host penalty, which is exactly the habit the decoy is
    # aimed at.
    n=0
    for ip in ${RANGE_STALE_A:-}; do
        n=$(( n + 1 ))
        printf 'old-%s%d\t%s\n' "${RANGE_ORG_PREFIX}" "$n" "$ip"
    done
} > "$zone_data"

for h in "${HOSTS[@]}"; do
    ctn="$( ctn_of "$h" )"
    cls="${TARGET_CLASS[$h]}"
    docker exec "$ctn" mkdir -p /etc/minilabs/profiles
    docker cp "$LAB_DIR/image/profiles/." "$ctn:/etc/minilabs/profiles/"
    docker cp "$zone_data" "$ctn:/etc/minilabs/zone.data"
    # Modes are set explicitly rather than left to the ambient umask, which is
    # 0022 under a rootful daemon and 0000 under a rootless one.
    docker exec "$ctn" sh -c 'chmod 755 /etc/minilabs /etc/minilabs/profiles; chmod 644 /etc/minilabs/profiles/*.sh /etc/minilabs/zone.data'
    # What this machine is, written where the scorer reads it back off the
    # running container like everything else it grades. The learner never sees
    # this file; what they see is the four signals it was decided from.
    docker exec "$ctn" sh -c "printf '%s\n' '$cls' > /etc/minilabs/class; chmod 644 /etc/minilabs/class"

    # ONE INVOCATION PER SERVICE. A host runs a primary service and may run more:
    # the `chatty` mutator adds an SNMP agent to most machines and `noisy` adds
    # junk listeners. Each entry gets its own profile.env, holding only that
    # entry's ports, so a script that asks for "the first TCP port" gets its own
    # rather than whichever port happened to be first on the host.
    for entry in ${TARGET_SERVICES[$h]}; do
        prof="${entry%%:*}"
        specs="${entry#*:}"
        # -i is load-bearing: without it `docker exec` attaches no stdin, the
        # block below pipes into nothing, and the profile script starts with an
        # empty parameter file and no ports. It exits non-zero, but far enough
        # from the cause that the failure reads as a broken profile rather than
        # a lost pipe.
        {
            kv PROFILE_NAME    "${prof}"
            kv PROFILE_PORTS   "${specs//,/ }"
            kv PROFILE_IMPL    "${TARGET_IMPL[$h]}"
            kv PROFILE_PARAM   "${TARGET_PARAM[$h]}"
            kv FTP_PASV_MIN    "${FTP_PASV_MIN}"
            kv FTP_PASV_MAX    "${FTP_PASV_MAX}"
            kv CHAIN_ACCOUNT   "${CHAIN_ACCOUNT}"
            kv HOST_CLASS      "${cls}"
            kv CLASS_SYSDESCR  "${CLASS_SYSDESCR[$cls]}"
            kv ORG_NAME        "${RANGE_ORG_NAME}"
            kv ORG_ZONE        "${RANGE_ZONE}"
            kv ORG_PREFIX      "${RANGE_ORG_PREFIX}"
            kv ORG_TEAM        "${RANGE_ORG_TEAM}"
            kv ORG_SITES       "${RANGE_ORG_SITES}"
            kv ORG_DROP        "${RANGE_ORG_DROP}"
        } | docker exec -i "$ctn" sh -c "cat > /etc/minilabs/profile.env"
        log "configuring $ctn: profile $prof on ${specs:-no port}"
        docker exec "$ctn" sh "/etc/minilabs/profiles/${prof}.sh" \
            || { echo "profile $prof failed on $ctn" >&2; exit 1; }
    done
done

# ---------------------------------------------------------------------------
# 8. The chain.
#
# Every door on it opens because of a configuration a defender fixes by editing a
# file: a device shipped with its default credential still set, an account whose
# password is on a public list, a private key left in a home directory, its
# passphrase written down on an anonymous share, and a sudo rule that lets a
# service account read one file it has no business reading. Nothing here is an
# exploit and nothing here needs one.

chain_ctn() {   # <machine token> -> container name
    if [ "$1" = "$VAULT" ]; then echo "$VAULT_CTN"; else ctn_of "$1"; fi
}

# 8a. The split key, on ranges three layers deep and more.
#
# The private key is generated inside the foothold host rather than baked into
# the image, so two ranges never share one. Its passphrase came off the seed and
# is sitting on the anonymous share, which is the other branch: the key alone
# opens nothing, and so does the passphrase alone.
if [ -n "$VAULT_NET" ]; then
    foot_ctn="$( ctn_of "$CHAIN_FOOTHOLD" )"
    log "generating the vault key on $foot_ctn"
    docker exec -i "$foot_ctn" sh -s "$CHAIN_PASSPHRASE" "$CHAIN_ACCOUNT" <<'KEYGEN'
set -eu
passphrase="$1"; account="$2"
tmp=/tmp/chainkey
rm -f "$tmp" "$tmp.pub"
ssh-keygen -q -t ed25519 -N "$passphrase" -C "${account}@backup" -f "$tmp"

# Into every login home on this host, because which account the learner arrives
# as depends on which credential they found.
for home in /root /home/*; do
    [ -d "$home" ] || continue
    mkdir -p "$home/.ssh"
    cp "$tmp" "$home/.ssh/id_ed25519"
    cp "$tmp.pub" "$home/.ssh/id_ed25519.pub"
    cat > "$home/.ssh/README-backup.txt" <<NOTE
This is the key the overnight backup job uses to reach the offsite box.

It is passphrase-protected. The passphrase is NOT on this machine: it is written
down in the runbook, which lives in the document drop with the rest of the
operations paperwork.

  ssh -i ~/.ssh/id_ed25519 ${account}@<the offsite box>
NOTE
    owner="$( stat -c '%u:%g' "$home" )"
    chown -R "$owner" "$home/.ssh"
    chmod 700 "$home/.ssh"
    chmod 600 "$home/.ssh/id_ed25519"
    chmod 644 "$home/.ssh/id_ed25519.pub" "$home/.ssh/README-backup.txt"
done
rm -f "$tmp"
KEYGEN

    # The key is a finding, so the foothold host records it the way a profile
    # records one. It is appended rather than written, because the profile script
    # that ran on this host earlier put its own tokens in the same file.
    docker exec "$foot_ctn" sh -c \
        'grep -qx leaked-key /etc/minilabs/intel 2>/dev/null || echo leaked-key >> /etc/minilabs/intel'

    pubkey="$( docker exec "$foot_ctn" cat "/root/.ssh/id_ed25519.pub" )"

    # 8b. Whatever the key opens: the vault always, and an SSH pivot host as well
    #     on a four-layer range. The account is created with a real password
    #     rather than left as `adduser -D` makes it, because that leaves the
    #     shadow entry locked with a `!` and sshd refuses the account even for a
    #     key it would otherwise accept. Password authentication is off in every
    #     sshd config here, so the password cannot be used to log in; it exists
    #     only so the account is not locked.
    open_to_key() {   # <container> [also drop the private key in]
        local c="$1" carry="${2:-no}"
        docker exec -i "$c" sh -s "$CHAIN_ACCOUNT" "$pubkey" <<'AUTH'
set -eu
account="$1"; pubkey="$2"
id "$account" >/dev/null 2>&1 || adduser -D -s /bin/ash "$account"
# `adduser -D` leaves the shadow entry locked with a bare `!`, and sshd refuses a
# locked account even for a key it would otherwise accept, so the login fails
# with nothing in the client's output that points at the cause. Giving the
# account a real password unlocks it. The password itself is random and is never
# written down anywhere: password authentication is off in every sshd config on
# this range, so it cannot be used to log in.
pw="$( head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n' )"
printf '%s:%s\n' "$account" "$pw" | chpasswd >/dev/null 2>&1
home="$( getent passwd "$account" | cut -d: -f6 )"
mkdir -p "$home/.ssh"
printf '%s\n' "$pubkey" > "$home/.ssh/authorized_keys"
chown -R "$account:$account" "$home/.ssh"
chmod 700 "$home/.ssh"
chmod 600 "$home/.ssh/authorized_keys"
AUTH
        if [ "$carry" = carry ]; then
            # A four-layer range needs the key on the pivot as well, or the last
            # hop cannot be made from the machine the vault's filter permits.
            docker exec "$foot_ctn" cat /root/.ssh/id_ed25519 \
                | docker exec -i "$c" sh -c "
                    home=\$( getent passwd '$CHAIN_ACCOUNT' | cut -d: -f6 )
                    mkdir -p \"\$home/.ssh\"
                    cat > \"\$home/.ssh/id_ed25519\"
                    chown -R '$CHAIN_ACCOUNT:$CHAIN_ACCOUNT' \"\$home/.ssh\"
                    chmod 600 \"\$home/.ssh/id_ed25519\""
        fi
    }

    if [ -n "$CHAIN_PIVOT" ]; then
        log "authorising the vault key on the pivot $( ctn_of "$CHAIN_PIVOT" )"
        open_to_key "$( ctn_of "$CHAIN_PIVOT" )" carry
    fi

    # The vault runs one service and it is sshd, key-only. It is configured here
    # rather than through a profile script because the vault is not a drawn host
    # and nothing about it is drawn: it is the same machine on every range that
    # has one.
    log "configuring the vault $VAULT_CTN"
    docker exec "$VAULT_CTN" mkdir -p /etc/minilabs
    open_to_key "$VAULT_CTN"
    docker exec -i "$VAULT_CTN" sh -s <<'VAULTSSH'
set -eu
ssh-keygen -A >/dev/null 2>&1
# UsePAM is deliberately absent. This image's OpenSSH is built without PAM, so
# the option is not merely ignored: sshd prints "Unsupported option UsePAM" on
# every start, which put a warning in the middle of every spawn's output for a
# setting that was already the effective behaviour.
cat > /etc/ssh/sshd_config <<CONF
Port 22
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
Subsystem sftp /usr/lib/ssh/sftp-server
CONF
pkill -x sshd 2>/dev/null || true
i=25; while [ $i -gt 0 ] && pgrep -x sshd >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
/usr/sbin/sshd -f /etc/ssh/sshd_config
VAULTSSH
fi

# 8c. The milestone tokens.
#
# Two copies of each, and the difference between them is the whole point. The
# copy under /etc/minilabs is root-owned and mode 600, and it is what truth.sh
# reads back at scoring time; the account the chain logs in as cannot read it. The
# copy in each login home is the one the learner finds, and it is the only way to
# come by the token by playing.
for step in "${CHAIN_STEPS[@]}"; do
    name="${step%%:*}"; machine="${step#*:}"
    ctn="$( chain_ctn "$machine" )"
    log "planting the $name token on $ctn"
    docker exec -i "$ctn" sh -s "$name" "${CHAIN_TOKEN[$name]}" <<'PLANT'
set -eu
name="$1"; token="$2"
mkdir -p /etc/minilabs
printf '%s|%s\n' "$name" "$token" >> /etc/minilabs/flagtoken
chown root:root /etc/minilabs/flagtoken
chmod 600 /etc/minilabs/flagtoken

# Into /root and every login home. Which account a learner arrives as depends on
# which credential they found, so the token is put where any of them will see it
# rather than only under the one this script happened to think of.
for home in /root /home/*; do
    [ -d "$home" ] || continue
    printf '%s\n' "$token" > "${home}/${name}.txt"
    owner="$( stat -c '%u:%g' "$home" )"
    chown "$owner" "${home}/${name}.txt"
    chmod 644 "${home}/${name}.txt"
done
PLANT
done

# 8d. The last door: the flag, and the sudo rule that reads it.
#
# `sudo -l` names the one command this account may run as root, and that command
# reads one file. It is a misconfiguration of the kind a real service account
# accumulates, it is fixed by deleting one line, and it needs nothing that could
# be mistaken for an exploit.
flag_ctn="$( chain_ctn "$CHAIN_FLAG_MACHINE" )"
log "planting the flag on $flag_ctn behind a sudo rule"
docker exec -i "$flag_ctn" sh -s "$CHAIN_FLAG_TOKEN" "$VAULT_FLAG_FILE" <<'FLAG'
set -eu
token="$1"; path="$2"
mkdir -p /etc/minilabs "$( dirname "$path" )"
printf 'flag|%s\n' "$token" >> /etc/minilabs/flagtoken
chmod 600 /etc/minilabs/flagtoken

cat > "$path" <<BODY
Kiwi Freight Ltd - offsite backup index

  ${token}

If you are reading this and you are not the backup job, the sudo rule that let
you read it is the finding. Report it.
BODY
chown root:root "$path"
chmod 600 "$path"

# Every non-root login account on this machine, so the rule is reachable
# whichever credential the learner arrived with.
mkdir -p /etc/sudoers.d
: > /etc/sudoers.d/backup
for home in /home/*; do
    [ -d "$home" ] || continue
    u="$( basename "$home" )"
    id "$u" >/dev/null 2>&1 || continue
    printf '%s ALL=(root) NOPASSWD: /bin/cat %s\n' "$u" "$path" >> /etc/sudoers.d/backup
done
chmod 440 /etc/sudoers.d/backup
FLAG

echo
echo "SEED ${RANGE_SEED} TIER ${RANGE_TIER} SHAPE ${RANGE_SHAPE} MUTATOR ${RANGE_MUTATOR}"
if [ -n "$RANGE_GIVEN" ]; then
    echo "You are at ${ATTACKER_IP}. You are given: ${RANGE_GIVEN}"
else
    echo "You are at ${ATTACKER_IP}, gateway ${ATT_GW}. You are given nothing else."
fi
echo "Record findings on the attacker with \`report\`; grade them with the Score action."
