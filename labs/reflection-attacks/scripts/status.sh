#!/usr/bin/env bash
# Show what the lab is doing: containers, per-device addressing, the router's
# filter state, and the self-contained oracle — does a forged-source query still
# reach a reflector. It fires one spoofed query (source = the victim) at each
# reflector and reports whether the reflector received it. REACHES before the
# defence, BLOCKED after. No MATRIX needed.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

echo "== containers =="
docker ps --filter "name=${AS}_L3_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

echo "== router: forwarding + source-address verification state =="
docker exec "$ROUTER_CTN" sysctl -n net.ipv4.ip_forward 2>/dev/null \
    | sed 's/^/  ip_forward = /'
for ifc in "$R_CUST_IF" "$R_CORE_IF"; do
    v="$(docker exec "$ROUTER_CTN" sysctl -n "net.ipv4.conf.${ifc}.rp_filter" 2>/dev/null)"
    echo "  rp_filter($ifc) = ${v:-?}   (0 off, 1 strict uRPF, 2 loose)"
done
if docker exec "$ROUTER_CTN" nft list table ip bcp38 >/dev/null 2>&1; then
    echo "  nftables: bcp38 table present ->"
    docker exec "$ROUTER_CTN" nft list table ip bcp38 2>/dev/null | sed 's/^/    /'
else
    echo "  nftables: no bcp38 table"
fi
echo

for d in "${DEVICES[@]}"; do
    ctn="$(ctn_of "$d")"
    echo "== $d ($ctn) =="
    docker exec "$ctn" ip -brief addr show 2>/dev/null \
        | grep -vE '^lo ' | sed 's/^/  /'
done
echo

# The oracle: fire a forged-source query at each reflector and see if it arrives.
probe() {
    local proto="$1" refl_ip="$2" refl_ctn="$3" port="$4"
    docker exec -d "$refl_ctn" sh -c \
        "tcpdump -n -i $HOST_IF -w /tmp/probe.pcap 'udp dst port $port and src host $VICTIM_IP' >/dev/null 2>&1"
    sleep 0.4
    docker exec "$ATTACKER_CTN" reflect "$proto" "$refl_ip" "$VICTIM_IP" 2 >/dev/null 2>&1 || true
    sleep 0.8
    docker exec "$refl_ctn" pkill -f tcpdump 2>/dev/null || true
    sleep 0.3
    local n
    n="$(docker exec "$refl_ctn" sh -c 'tcpdump -nr /tmp/probe.pcap 2>/dev/null | wc -l' | tr -d ' ')"
    if [ "${n:-0}" -gt 0 ]; then
        echo "  REACHES  $proto ($refl_ip): forged-source query arrived ($n pkt)"
    else
        echo "  BLOCKED  $proto ($refl_ip): forged-source query did not arrive"
    fi
}

echo "== oracle: does a forged-source (src=$VICTIM_IP) query reach the reflector? =="
probe dns "$DNS_IP" "$DNS_CTN" 53
probe ntp "$NTP_IP" "$NTP_CTN" 123
