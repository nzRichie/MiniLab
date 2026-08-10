#!/bin/bash
# host3: the FTP service, at 104.1.0.87. Named for the container rather than for
# the service, so spawn.sh's output gives Part 2 away to nobody.
#
# Two things make this host the most interesting one in the /24, and they are
# independent of each other.
#
# First, anonymous login is enabled. Anyone who can reach port 21 can list and
# read the share without an account, which nmap's ftp-anon script reports as a
# finding rather than leaving the learner to try it by hand. The share holds an
# operations handover note that names the account used on the telnet host, so
# enumerating this service is what supplies the username Part 3 attacks.
#
# Second, this host does not answer ICMP echo requests. That is the lab's
# discovery lesson: a ping sweep of the /24 misses it completely, so the learner
# who trusts the sweep never scans the host holding the credentials. An nmap -sn
# with its default probe set still finds it, because that set also sends TCP to
# ports 80 and 443 and a live host answers a closed port with a RST.
set -e

ip address add 104.1.0.87/24 dev 104-S1 2>/dev/null || true
ip link set 104-S1 up
ip route add default via 104.1.0.1 2>/dev/null || true

# Silent to ping. Echo and timestamp requests are the two ICMP probes a host
# discovery sweep uses; drop both so nothing but a TCP probe reveals this host.
# Applied with iptables inside this container's own network namespace, so it
# needs NET_ADMIN and nothing more.
iptables -F INPUT 2>/dev/null || true
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
iptables -A INPUT -p icmp --icmp-type timestamp-request -j DROP

# The anonymous share. vsftpd refuses to start if the anonymous root is writable
# by the user it chroots into, so the directory is left read-only on purpose.
FTP_ROOT=/var/lib/ftp
mkdir -p "$FTP_ROOT/pub"

cat > "$FTP_ROOT/pub/handover.txt" <<'EOF'
Kiwi Freight Ltd - network operations handover
----------------------------------------------
Left by the outgoing contractor. Whoever picks this up, please work through it.

 * This document drop still allows anonymous FTP. It was set up that way so the
   freight manifests could be dropped without accounts, and it was meant to be
   temporary. It should be closed.

 * Remote administration on the switch at 104.1.0.201 is still plain telnet, not
   SSH. Everyone in operations shares the 'netadmin' account on that box. Moving
   it to SSH with per-user keys has been on the list for a long time.

 * The password on that account has not been rotated since the account was
   created, and it is not written down anywhere, so ask around in operations
   before you lock yourself out of the switch.
EOF

chown -R root:root "$FTP_ROOT"
chmod 555 "$FTP_ROOT"
chmod 755 "$FTP_ROOT/pub"
chmod 644 "$FTP_ROOT/pub/handover.txt"

# Anonymous read-only. The default 220 banner is kept, so it still names the
# software and version and nmap -sV can identify it.
cat > /etc/vsftpd/vsftpd-lab.conf <<'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=YES
local_enable=NO
write_enable=NO
anon_upload_enable=NO
anon_mkdir_write_enable=NO
no_anon_password=YES
anon_root=/var/lib/ftp
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
pasv_enable=YES
pasv_min_port=30000
pasv_max_port=30100
seccomp_sandbox=NO
background=YES
secure_chroot_dir=/var/lib/vsftpd/empty
EOF
mkdir -p /var/lib/vsftpd/empty
# The mode is set explicitly rather than left to the ambient umask. vsftpd
# chroots its pre-authentication process into secure_chroot_dir and refuses
# every session with "500 OOPS: refusing to run with writable root inside
# chroot()" if that directory is writable. `docker exec` runs with umask 0022
# under a rootful daemon but 0000 under a rootless one, where mkdir would leave
# this directory 777 and break the anonymous login that Parts 3 to 5 depend on.
chmod 755 /var/lib/vsftpd /var/lib/vsftpd/empty

# Restart cleanly so a reset always comes up with a fresh listener.
pkill -x vsftpd 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -x vsftpd >/dev/null 2>&1 || break; sleep 0.2; done
vsftpd /etc/vsftpd/vsftpd-lab.conf || { echo "vsftpd failed to start" >&2; exit 1; }
# What this prints is streamed into the TUI's Spawn panel, so it names no
# address, port, service or account: the learner reads this before they have
# scanned anything, and all of that is what Parts 1 to 3 have them find.
echo "host3 configured"
