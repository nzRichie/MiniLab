#!/bin/bash
# NTP reflector starter config (honest infrastructure, pre-armed). A time server
# that also answers mode-6 control queries. It is the lab's second, unrelated
# reflector: a different protocol on a different port that bounces traffic the same
# way, so reflection is shown to be a property of connectionless services, not of
# DNS. NTP's classic reflection vector was the mode-7 "monlist" command, removed
# years ago; this server shows the vector that replaced it, a mode-6 "readvar",
# which returns the server's whole variable list to whoever asks.
#
# The one deliberately-open choice is the restrict line: the lab subnets are
# allowed to run control queries (no `noquery`). A hardened server would refuse
# them from clients; this one answers anyone in 102.0.0.0/8, which is what makes
# it usable as a reflector.
set -e

ip address add 102.1.0.123/24 dev 102-S1 2>/dev/null || true
ip link set 102-S1 up
ip route add default via 102.1.0.1 2>/dev/null || true

mkdir -p /var/lib/ntpsec
cat > /etc/ntp-lab.conf <<'EOF'
driftfile /var/lib/ntpsec/ntp.drift
# Serve time from the local clock as an orphan (no upstream peers on the isolated
# lab), so the daemon is up and answering immediately.
tos orphan 5
# Default: refuse configuration and peering, the sane baseline.
restrict default nomodify nopeer
# The vulnerability: the whole lab AS may run mode-6 control queries unrestricted,
# so a "readvar" from any lab host (or a forged one) gets the full reply.
restrict 102.0.0.0 mask 255.0.0.0
EOF

# Restart cleanly so a reset always comes up fresh.
pkill -x ntpd 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -x ntpd >/dev/null 2>&1 || break; sleep 0.2; done
ntpd -c /etc/ntp-lab.conf -g -N >/var/log/ntpd.log 2>&1 || {
    echo "ntpd failed to start; see /var/log/ntpd.log" >&2; exit 1; }
echo "ntp reflector up at 102.1.0.123 (mode-6 readvar open to 102.0.0.0/8)"
