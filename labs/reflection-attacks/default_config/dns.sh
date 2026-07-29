#!/bin/bash
# DNS reflector starter config (honest infrastructure, pre-armed). An ordinary
# authoritative server. It serves one synthetic name, reflect.lab, whose TXT
# record a forged-source query asks for. The server is not misconfigured in any
# exotic way; it answers the query it is asked, which is all a reflector has to do.
# The attacker abuses that by asking with a forged source, so the reply lands on
# the victim instead of the attacker.
set -e

ip address add 102.1.0.53/24 dev 102-S1 2>/dev/null || true
ip link set 102-S1 up
ip route add default via 102.1.0.1 2>/dev/null || true

# One synthetic TXT record. Its content does not matter; what matters is that a
# query draws a reply the attacker can steer at the victim by forging the source.
# Kept short so the whole reply fits one UDP DNS message.
PAYLOAD="reflection-lab record; a query for reflect.lab returns this to whatever source the query claims"
cat > /etc/dnsmasq-lab.conf <<EOF
# Reflector for the lab. Authoritative only; no recursion, no upstream, no local
# hosts file. Serves the single name reflect.lab.
port=53
no-resolv
no-hosts
log-queries
txt-record=reflect.lab,"$PAYLOAD"
EOF

# Restart cleanly so a reset always comes up with a fresh listener.
pkill -x dnsmasq 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -x dnsmasq >/dev/null 2>&1 || break; sleep 0.2; done
dnsmasq -C /etc/dnsmasq-lab.conf || { echo "dnsmasq failed to start" >&2; exit 1; }
echo "dns reflector up at 102.1.0.53 (serves reflect.lab)"
