#!/bin/bash
# Legitimate DHCP server starter config — pre-armed with `Config` (proposal: the
# honest infrastructure boots ready). Static address 101.0.0.1, and it hands that
# same address out as the default gateway. A small pool (101.0.0.100-120, 21
# addresses) keeps starvation quick to watch.
set -e

ip address add 101.0.0.1/24 dev 101-S1 2>/dev/null || true
ip link set 101-S1 up

cat > /etc/dhcp/dhcpd.conf <<'EOF'
# Legitimate DHCP server for the 101.0.0.0/24 lab LAN.
# Long leases (2h) so nothing expires and frees an address mid-lab: once the
# attacker's flood owns the pool, it keeps owning it for the whole session, which
# is what makes the starvation result stable to read.
default-lease-time 7200;
max-lease-time 7200;
authoritative;
ping-check false;                   # offer immediately, don't probe first (fast lab)

subnet 101.0.0.0 netmask 255.255.255.0 {
    range 101.0.0.100 101.0.0.120;
    option subnet-mask 255.255.255.0;
    option routers 101.0.0.1;       # clients are told the SERVER is the gateway
}
EOF

# Start fresh: clear any prior leases so the pool is full on every (re)start.
# dhcpd keeps its lease database in memory, so refilling the pool means restarting
# the process, not just truncating the file. Stop the old one (by pidfile, then by
# name) and wait for it to exit, or the new process fails to bind the interface
# ("There's already a DHCP server running"). Used by reset.sh, which restarts us.
[ -f /var/run/dhcpd.pid ] && kill "$(cat /var/run/dhcpd.pid)" 2>/dev/null || true
pkill -x dhcpd 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -x dhcpd >/dev/null 2>&1 || break; sleep 0.2; done
: > /var/lib/dhcp/dhcpd.leases
dhcpd -4 -q -cf /etc/dhcp/dhcpd.conf -lf /var/lib/dhcp/dhcpd.leases \
      -pf /var/run/dhcpd.pid 101-S1 2>/var/log/dhcpd.log || {
    echo "dhcpd failed to start; see /var/log/dhcpd.log" >&2
    cat /var/log/dhcpd.log >&2
    exit 1
}
echo "legit dhcpd serving 101.0.0.100-130, gateway 101.0.0.1"
