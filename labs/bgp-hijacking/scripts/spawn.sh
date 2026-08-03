#!/usr/bin/env bash
# Spawn the BGP prefix-hijacking lab: six single-router ASes wired in the fixed
# topology from lib.sh, each with one host behind it, plus the RPKI infrastructure
# (a Krill RIR and a Routinator validator). Self-contained -- drives docker and the
# veth primitives directly, WITHOUT platform/startup.sh (proposal RQ1). Every
# inter-AS link is a Layer-3 point-to-point veth pair; there is no switch and no
# OVS. The routers run FRR and are configured only over vtysh; the hosts are the
# bash side (curl, traceroute, the identity banners).
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[spawn] $*"; }

# Docker reachability is the only host prerequisite (covers group membership and a
# stopped daemon). No ovs/frr host check: both live inside the images.
command -v docker >/dev/null 2>&1 || { echo "docker not found on host" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
    echo "cannot reach the Docker daemon; is it running and are you in the 'docker' group?" >&2
    exit 1
}

if docker ps -a --format '{{.Names}}' | grep -q "$LAB_FILTER"; then
    echo "Lab already spawned (containers matching ${LAB_FILTER} exist). Run teardown.sh first." >&2
    exit 1
fi

ensure_images

# 1. Containers. Routers get the three capabilities FRR's zebra needs
#    (net_admin + net_raw + sys_admin) and IP forwarding on from birth; rp_filter
#    is off so BGP's potentially asymmetric paths are never dropped. Hosts get
#    net_admin to set their own address. No data-plane network: the veth links are
#    the only fabric.
for as in "${ASES[@]}"; do
    rc="$( router_ctn "$as" )"
    log "starting router $rc"
    docker run -d --name "$rc" --network=none \
        --cap-add=NET_ADMIN --cap-add=NET_RAW --cap-add=SYS_ADMIN \
        --sysctl net.ipv4.ip_forward=1 \
        --sysctl net.ipv4.conf.all.rp_filter=0 \
        --sysctl net.ipv4.conf.default.rp_filter=0 \
        --hostname "as${as}" \
        "$ROUTER_IMAGE" >/dev/null

    hc="$( host_ctn "$as" )"
    log "starting host $hc (${AS_ROLE[$as]})"
    docker run -d --name "$hc" --network=none \
        --cap-add=NET_ADMIN --hostname "${AS_ROLE[$as]}${as}" \
        "$HOST_IMAGE" >/dev/null
done

# 2. The RPKI plane. These two are the one part of the lab that is not veth-only:
#    they share a private docker bridge so that Krill's web UI can be published to
#    the host, which needs a bridge with NAT. The publish is bound to 127.0.0.1, so
#    the portal is reachable from a browser on this machine and from nowhere else.
#    No router is ever attached to this network: the validator reaches each ROV
#    router over its own point-to-point veth, wired below.
log "creating the RPKI management network ${RPKI_NET}"
docker network inspect "$RPKI_NET" >/dev/null 2>&1 \
    || docker network create --subnet "$RPKI_NET_SUBNET" "$RPKI_NET" >/dev/null

log "starting the RIR ($RIR_CTN, Krill)"
docker run -d --name "$RIR_CTN" \
    --network "$RPKI_NET" --ip "$RIR_NET_IP" \
    --hostname "$RIR_FQDN" --add-host "${RIR_FQDN}:${RIR_NET_IP}" \
    -p "127.0.0.1:${RIR_PORT}:${RIR_PORT}" \
    -e RIR_FQDN="$RIR_FQDN" -e RIR_PORT="$RIR_PORT" -e KRILL_TOKEN="$KRILL_TOKEN" \
    -e KRILL_CLI_SERVER="https://localhost:${RIR_PORT}/" -e KRILL_CLI_TOKEN="$KRILL_TOKEN" \
    "$RIR_IMAGE" >/dev/null

log "starting the validator ($VALIDATOR_CTN, Routinator)"
docker run -d --name "$VALIDATOR_CTN" \
    --network "$RPKI_NET" --ip "$VALIDATOR_NET_IP" \
    --cap-add=NET_ADMIN --add-host "${RIR_FQDN}:${RIR_NET_IP}" \
    -e RIR_FQDN="$RIR_FQDN" -e RIR_PORT="$RIR_PORT" -e RTR_PORT="$RTR_PORT" \
    "$VALIDATOR_IMAGE" >/dev/null

# 3. Privileged wiring via the helper container (docker access is all the learner
#    needs; the helper holds the netlink privileges). Trapped so it always goes.
helper_start
trap helper_stop EXIT

i=0
# Move one end of a fresh veth pair into a container, rename and up it.
plug() {
    local ctn="$1" want_if="$2" tmp="$3" pid
    pid="$( docker inspect -f '{{.State.Pid}}' "$ctn" )"
    helper_bind_netns "$pid"
    helper ip link set "$tmp" netns "$pid"
    helper ip netns exec "$pid" ip link set dev "$tmp" name "$want_if"
    helper ip netns exec "$pid" ip link set dev "$want_if" up
}
# One point-to-point veth between two containers' named interfaces.
wire() {
    local ctnA="$1" ifA="$2" ctnB="$3" ifB="$4"
    i=$(( i + 1 ))
    local ta="v${i}a" tb="v${i}b"
    helper ip link add "$ta" type veth peer name "$tb"
    plug "$ctnA" "$ifA" "$ta"
    plug "$ctnB" "$ifB" "$tb"
}

# 3a. Inter-AS links (eBGP over /30). For link "a b", a's interface is to_as<b>.
for link in "${LINKS[@]}"; do
    read -r a b _ <<<"$link"
    log "wiring AS${a} <-> AS${b}"
    wire "$( router_ctn "$a" )" "$( peer_if "$b" )" "$( router_ctn "$b" )" "$( peer_if "$a" )"
done

# 3b. Host links (router <-> its host).
for as in "${ASES[@]}"; do
    log "wiring AS${as} router <-> host"
    wire "$( router_ctn "$as" )" "$HOST_IF_ROUTER" "$( host_ctn "$as" )" "$HOST_IF_HOST"
done

# 3c. RTR links (validator <-> each ROV router). The router end is addressed later
#     by that router's own vtysh config, like every other router interface. The
#     validator end is addressed here through the helper, because the upstream
#     Routinator image carries no iproute2 of its own.
for link in "${RPKI_LINKS[@]}"; do
    read -r as vip _ subnet <<<"$link"
    log "wiring validator <-> AS${as} (RTR)"
    wire "$VALIDATOR_CTN" "$( rpki_if_validator "$as" )" \
         "$( router_ctn "$as" )" "$( rpki_if_router )"
    vpid="$( docker inspect -f '{{.State.Pid}}' "$VALIDATOR_CTN" )"
    helper_bind_netns "$vpid"
    helper_addr "$vpid" "$( rpki_if_validator "$as" )" "${vip}/${subnet##*/}"
done

# 4. Wait for each router's FRR, then apply its config over vtysh.
for as in "${ASES[@]}"; do
    rc="$( router_ctn "$as" )"
    log "waiting for FRR in $rc"
    wait_for_vtysh "$rc"
    log "configuring $rc via default_config/r${as}.sh"
    docker cp "$LAB_DIR/default_config/r${as}.sh" "$rc:/home/r${as}.sh"
    docker exec "$rc" chmod 755 "/home/r${as}.sh"
    docker exec "$rc" "/home/r${as}.sh"
done

# 5. Host addressing (generic host-setup.sh; AS6 also gets the impostor secondary).
for as in "${ASES[@]}"; do
    hc="$( host_ctn "$as" )"
    log "configuring $hc"
    docker cp "$LAB_DIR/default_config/host-setup.sh" "$hc:/home/host-setup.sh"
    docker exec "$hc" chmod 755 /home/host-setup.sh
    if [ "$as" -eq "$ATTACKER_AS" ]; then
        docker exec "$hc" /home/host-setup.sh "${AS_HOST_IP[$as]}/24" "${AS_GW[$as]}" "${IMPOSTOR_HOST_IP}/25"
    else
        docker exec "$hc" /home/host-setup.sh "${AS_HOST_IP[$as]}/24" "${AS_GW[$as]}"
    fi
done

# 6. Identity banners, detached so they outlive the exec. The victim announces
#    itself as legitimate; the attacker's impostor names itself, so a captured
#    curl to the service IP reads back who actually answered.
log "starting victim banner (AS1) and attacker impostor banner (AS6)"
docker exec -d "$( host_ctn 1 )" banner-server "$VICTIM_BANNER"
docker exec -d "$( host_ctn "$ATTACKER_AS" )" banner-server "$ATTACKER_BANNER"

# 7. Bootstrap the RPKI plane while BGP is settling.
log "waiting for Krill to answer"
krill_up=0
for _ in $(seq 1 90); do
    if krillc list >/dev/null 2>&1; then krill_up=1; break; fi
    sleep 1
done
if [ "$krill_up" -ne 1 ]; then
    echo "[spawn] WARNING: Krill did not come up; Part 2 of the handout will not work" >&2
else
    # The validator cannot verify Krill's TLS until it holds the root certificate
    # Krill generated at first boot, and its start script blocks until this lands.
    log "handing the RIR root certificate to the validator"
    docker cp "$RIR_CTN:/var/krill/data/ssl/root.crt" "/tmp/minilabs-rir-root.$$.crt" >/dev/null
    docker cp "/tmp/minilabs-rir-root.$$.crt" "$VALIDATOR_CTN:/home/routinator/root.crt" >/dev/null
    rm -f "/tmp/minilabs-rir-root.$$.crt"

    # Enrol one CA per AS that holds address space in this lab. Each is a child of
    # the testbed trust anchor and is issued a certificate for exactly the resources
    # named here -- which is the whole point: AS6's certificate covers 6.0.0.0/24
    # and nothing inside the victim's block, so the hijack can never be signed.
    #
    # The exchange is the RFC 8183 dance (child request -> parent response, then
    # publisher request -> repository response). It runs entirely inside the RIR
    # container, so no XML ever touches the host.
    for spec in "${KRILL_CAS[@]}"; do
        read -r ca resources asn <<<"$spec"
        log "enrolling CA ${ca} (${resources}, AS${asn}) with the testbed trust anchor"
        docker exec "$RIR_CTN" sh -c "
            set -e
            krillc add --ca ${ca} >/dev/null 2>&1 || true
            krillc parents request --ca ${ca} > /tmp/${ca}-child-req.xml
            krillc children add --ca testbed --child ${ca} --asn ${asn} \
                --ipv4 ${resources} --request /tmp/${ca}-child-req.xml > /tmp/${ca}-parent-res.xml
            krillc parents add --ca ${ca} --parent testbed --response /tmp/${ca}-parent-res.xml >/dev/null
            krillc repo request --ca ${ca} > /tmp/${ca}-pub-req.xml
            krillc pubserver publishers add --request /tmp/${ca}-pub-req.xml > /tmp/${ca}-repo-res.xml
            krillc repo configure --ca ${ca} --response /tmp/${ca}-repo-res.xml >/dev/null
        " >/dev/null 2>&1 || log "WARNING: enrolling ${ca} reported an error"
        krill_ca_ready "$ca" || log "WARNING: CA ${ca} is not active yet"
    done

    # AS6 arrives as a responsible operator that has already registered its own
    # block. AS1 deliberately gets no ROA: creating it is the learner's job in
    # Part 2, and its absence is why the hijack works at all.
    for spec in "${PRELOADED_ROAS[@]}"; do
        read -r ca prefix asn <<<"$spec"
        log "preloading ROA ${prefix} => AS${asn} for ${ca}"
        krillc roas update --ca "$ca" --add "${prefix} => ${asn}" >/dev/null 2>&1 \
            || log "WARNING: could not add the ${ca} ROA"
    done
fi

# 8. Wait for BGP to converge end-to-end: the attacker learning the victim's prefix
#    with origin AS1 means every session on the path is up and routes have
#    propagated across the whole island.
log "waiting for BGP convergence"
converged=0
for _ in $(seq 1 60); do
    if [ "$( best_path_origin "$( router_ctn "$ATTACKER_AS" )" "$VICTIM_PREFIX" )" = "1" ]; then
        converged=1; break
    fi
    sleep 1
done
if [ "$converged" -ne 1 ]; then
    echo "[spawn] WARNING: BGP did not converge within the timeout; check status.sh" >&2
fi

log "lab is up. Check it with:  $LAB_DIR/scripts/status.sh"
log "RIR portal: ${KRILL_UI_URL}  (token: ${KRILL_TOKEN})"
