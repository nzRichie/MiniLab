#!/bin/bash
# host4: the telnet service, at 104.1.0.201. Named for the container rather than
# for the service, so spawn.sh's output gives Part 2 away to nobody.
#
# This is the host Part 3 attacks, and it is weak in three separate ways that
# compound.
#
#  * The protocol is telnet, so the session carries the username and password in
#    cleartext and anyone on the path can read them.
#  * The account is shared across a team and its password is one of the fifty
#    most common passwords, so guessing it needs a wordlist and no exploit.
#  * A failed login costs an attacker nothing: the connection closes, and there
#    is no lockout, no delay, and no record kept.
#
# The password is set here but is never written into any page, file or banner the
# learner can read. It is recovered by guessing and only by guessing.
set -e

ip address add 104.1.0.201/24 dev 104-S1 2>/dev/null || true
ip link set 104-S1 up
ip route add default via 104.1.0.1 2>/dev/null || true

USER=netadmin
PASS=trustno1

# The shared operations account. Recreated on every reset so a learner who
# changed the password during the lab still starts Part 3 from the same place.
if ! id "$USER" >/dev/null 2>&1; then
    adduser -D -s /bin/ash "$USER"
fi
echo "${USER}:${PASS}" | chpasswd >/dev/null 2>&1

# Something for a learner who gets in to find, so the login is worth reaching.
cat > "/home/${USER}/manifest-schedule.txt" <<'EOF'
Freight manifest upload schedule
  Mon 0600  Auckland    -> document drop
  Wed 0600  Tauranga    -> document drop
  Fri 0600  Christchurch-> document drop
Contact network operations if an upload window is missed.
EOF
chown "${USER}:${USER}" "/home/${USER}/manifest-schedule.txt"

# busybox telnetd, with the lab's own one-shot login front-end instead of
# /bin/login. image/lab-login explains why: busybox login re-prompts three times
# on one connection, which desyncs hydra's telnet module permanently after the
# first wrong password. Closing the session on a failed login is also what the
# device this host stands in for really does.
pkill -x telnetd 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -x telnetd >/dev/null 2>&1 || break; sleep 0.2; done
/usr/sbin/telnetd -l /usr/local/bin/lab-login -p 23 \
    || { echo "telnetd failed to start" >&2; exit 1; }
# What this prints is streamed into the TUI's Spawn panel, so it names no
# address, port, service or account: the learner reads this before they have
# scanned anything, and all of that is what Parts 1 to 3 have them find.
echo "host4 configured"
