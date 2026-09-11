#!/bin/sh
# Starter config for the bastion: the machine on the DMZ segment, alone.
#
# It is called a bastion because of where it sits, not because of anything it is
# configured with. At spawn it is an ordinary host that happens to be on its own
# segment: it accepts a password from anywhere that can reach it, it will forward
# a connection to any destination it can reach, and nothing anywhere says that
# the machines behind the router should only be reached through it. Parts 2, 3
# and 4 are what turn its position into a policy.
set -eu

PREFIXLEN=24
BASTION_IP="114.1.0.2"
EDGE_DMZ_IP="114.1.0.1"

ROOT_PASS="Stavanger-4417"
JUMP_USER="jump"
JUMP_PASS="Kirkenes-9302"

SSHD_LOG="/var/log/bastion-sshd.log"
SSHD_PID="/run/sshd.pid"
SSHD_CONFIG="/etc/ssh/sshd_config"

ip addr replace "${BASTION_IP}/${PREFIXLEN}" dev 114-dmz
ip link set 114-dmz up
ip route replace default via "$EDGE_DMZ_IP"

# Create one account, give it a password, and leave it holding no key.
#
# The account already exists when the lab boots because the site's operators
# already exist; what does not exist is any key, any restriction on where the
# account may be reached from, and any reason it needs a password at all. All
# three are the learner's work.
#
# ~/.ssh is created here with mode 700 and left empty rather than left absent,
# because `docker exec` runs with umask 0022 under a rootful daemon and 0000
# under a rootless one. sshd refuses to read an authorized_keys file whose
# directory is writable by anyone but its owner, and it says nothing about why:
# the login simply falls through to the next method. Fixing the mode here means
# the learner never meets that failure for a reason the handout did not cause.
make_account() {   # <user> <password>
    if ! id -u "$1" >/dev/null 2>&1; then
        adduser -D -s /bin/sh "$1"
    fi
    echo "$1:$2" | chpasswd
    home="$( getent passwd "$1" | cut -d: -f6 )"
    rm -rf "${home}/.ssh"
    mkdir -p "${home}/.ssh"
    chown -R "$1:$1" "${home}/.ssh"
    chmod 700 "${home}/.ssh"
    chmod 755 "$home"
}

make_account "$JUMP_USER" "$JUMP_PASS"

# ---------------------------------------------------------------------------
# Stopping a daemon means waiting for it to let go of its port.
#
# `pkill` returns as soon as the signal is queued, not when the process has
# exited. Starting the replacement immediately then races the old process's exit,
# and the loser fails to bind. That failure is close to silent: sshd writes
# "Bind to port 22 on 0.0.0.0 failed: Address in use" into its own log and exits,
# and the PREVIOUS daemon is still listening with the configuration this script
# was run to replace. A reset that hits that race leaves a machine that reports
# itself reset and behaves as it did before, which is the worst thing a reset can
# do.
#
# The daemon is identified by its pid file, not by its name. `pkill -x sshd` does
# not match the OpenSSH listener at all: OpenSSH rewrites its own argv, so the
# process reads as "sshd: /usr/sbin/sshd -D -e [listener]" and an exact-name
# match finds nothing, returns success, and leaves the daemon running.
stop_and_wait() {   # <pid file> <process name> <port it must release>
    if [ -f "$1" ]; then
        kill "$( cat "$1" )" 2>/dev/null || true
    fi
    pkill -x "$2" 2>/dev/null || true     # a daemon started before the pid file existed
    i=0
    while [ "$i" -lt 50 ]; do
        netstat -tln 2>/dev/null | grep -q ":$3 " || return 0
        i=$(( i + 1 ))
        sleep 0.1
    done
    if [ -f "$1" ]; then kill -9 "$( cat "$1" )" 2>/dev/null || true; fi
    pkill -9 -x "$2" 2>/dev/null || true
    sleep 0.5
}

# ---------------------------------------------------------------------------
# sshd, as the site runs it before anybody has thought about who may reach it.
#
# The mini-internet base image ships a hardened sshd_config: PasswordAuthentication
# is no and AllowTcpForwarding is no, because every host in the course network is
# reached with a key. This lab needs the opposite, because turning those off and
# narrowing them is what the learner is graded on. A pristine copy is taken on the
# first run and restored on every run after it, so a learner's edits are replaced
# rather than sed-patched: patching a file somebody else has already edited is how
# a reset leaves a machine in a state neither the handout nor the answer key
# describes.
[ -f "${SSHD_CONFIG}.lab-orig" ] || cp "$SSHD_CONFIG" "${SSHD_CONFIG}.lab-orig"
cp "${SSHD_CONFIG}.lab-orig" "$SSHD_CONFIG"

# sshd uses the FIRST value it obtains for a keyword, so an appended line only
# takes effect where the shipped file left the keyword commented out. The two the
# file sets explicitly are rewritten in place instead.
sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' "$SSHD_CONFIG"
sed -i 's/^[[:space:]]*AllowTcpForwarding[[:space:]].*/AllowTcpForwarding yes/' "$SSHD_CONFIG"
grep -q '^PasswordAuthentication yes' "$SSHD_CONFIG" || echo 'PasswordAuthentication yes' >> "$SSHD_CONFIG"
grep -q '^AllowTcpForwarding yes'     "$SSHD_CONFIG" || echo 'AllowTcpForwarding yes'     >> "$SSHD_CONFIG"

# PermitRootLogin is commented in the shipped file, so the compiled-in default
# (prohibit-password) applies and a password login as root would be refused
# before the lab starts. Saying yes here is what makes Part 1's direct login
# observable.
echo 'PermitRootLogin yes' >> "$SSHD_CONFIG"

echo "root:${ROOT_PASS}" | chpasswd

# Host keys are generated once and kept, rather than regenerated on every reset:
# a reset that changed them would make the next login fail on a host-key
# mismatch, which has nothing to do with anything the lab teaches.
ssh-keygen -A >/dev/null

# -e sends the authentication log to stderr, which is redirected here. That file
# is half of this lab's oracle: a client's exit code says a login failed, and
# this file says which method sshd refused, for which account, and FROM WHICH
# ADDRESS, which is the field every restriction in this lab is written against.
stop_and_wait "$SSHD_PID" sshd 22
mkdir -p /var/log
: > "$SSHD_LOG"
chmod 644 "$SSHD_LOG"
/usr/sbin/sshd -D -e >>"$SSHD_LOG" 2>&1 &

echo "bastion: addressed; ${JUMP_USER} reachable by password from anywhere, forwarding unrestricted"
