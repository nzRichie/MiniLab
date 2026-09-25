#!/bin/sh
# Starter config for host6: the NTP reflector, and the second honest server.
#
# ntpsec 1.2.3, serving time from its own clock. The classic NTP amplifier was
# the mode-7 "monlist" command, which has been gone from every Alpine NTP
# package for years; this server carries the vector that replaced it. A mode-6
# control query asking the server to read out its variables is twelve bytes and
# draws back the whole variable list.
#
# Twelve bytes exactly. Eleven draws no reply at all and thirteen draws a
# twelve-byte error stub, which is worth knowing before spending an afternoon
# wondering why a hand-built packet gets nothing back.
#
# The one deliberately open choice is the restrict line. `restrict default
# nomodify nopeer` alone makes ntpsec answer no mode-6 query over the network at
# all; it takes an explicit flagless `restrict <subnet> mask <mask>` line for a
# subnet before a control query from it is answered. This server answers anyone
# in 129.0.0.0/8, which is what makes it usable as a reflector and is a
# configuration real servers have shipped with.
set -e

HOST_IP="129.1.0.53"
PREFIXLEN=24
FIELD_IF="129-S2"
GW="129.1.0.1"

ip addr replace "${HOST_IP}/${PREFIXLEN}" dev "$FIELD_IF"
ip link set "$FIELD_IF" up
ip route replace default via "$GW"

mkdir -p /var/lib/ntpsec
cat > /etc/ntp-lab.conf <<'EOF'
driftfile /var/lib/ntpsec/ntp.drift
# Serve time from the local clock as an orphan (there are no upstream peers on
# an isolated lab network), so the daemon is up and answering immediately.
tos orphan 5
# Default: refuse configuration and peering, the sane baseline.
restrict default nomodify nopeer
# The vulnerability: the whole lab may run mode-6 control queries unrestricted,
# so a readvar from any lab host, or from a forged one, gets the full reply.
restrict 129.0.0.0 mask 255.0.0.0
EOF

# Restart cleanly so a reset always comes up fresh.
pkill -x ntpd 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -x ntpd >/dev/null 2>&1 || break; sleep 0.2; done
ntpd -c /etc/ntp-lab.conf -g -N >/var/log/ntpd.log 2>&1 || {
    echo "ntpd failed to start; see /var/log/ntpd.log" >&2; exit 1; }

echo "host6: NTP reflector up at ${HOST_IP} (mode-6 readvar open to 129.0.0.0/8)"
