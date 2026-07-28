#!/bin/bash
# Victim starter config — a plain client with no defences (the defender side
# arrives with the gap to close). It has NO fixed address: it leases one over DHCP
# with busybox udhcpc, which applies the address, netmask, and the server-supplied
# default gateway via /usr/share/udhcpc/default.script. Whatever gateway the
# winning DHCP server names is the gateway this host will trust.
set -e

ip address flush dev 101-S1 2>/dev/null || true
ip route flush dev 101-S1 2>/dev/null || true
ip link set 101-S1 up

# One-shot lease: send up to 8 DISCOVERs 1s apart, apply the lease, then exit.
# The applied address and default route persist after udhcpc returns. Leases are
# long (see server.sh), so this address does not lapse during a lab session.
udhcpc -i 101-S1 -q -n -t 8 -T 1 >/var/log/udhcpc.log 2>&1 || {
    echo "victim got no DHCP lease (is the server up?)" >&2
    exit 1
}
echo "victim leased: $(ip -4 -brief addr show 101-S1 | awk '{print $3}'), default via $(ip route show default | awk '{print $3}')"
