#!/bin/sh
# The SSH service profile, on one drawn port. Two implementations, drawn per
# host: OpenSSH, and Dropbear, which is the one an embedded device ships.
#
# It runs no weakness. Password authentication is off and no account on it has a
# password worth guessing, so it is a service that identifies itself precisely
# and gives up nothing else. It is here because a real survey turns up services
# that are correctly configured, and a range in which every open port leads
# somewhere would teach a learner to expect that.
#
# What it does give up is its identity: the protocol sends the server's own
# version string before either side has authenticated anything, so the software
# and its exact release are readable from a bare connection. The two
# implementations announce different names as well as different numbers, which is
# what makes reading that string worth doing rather than assuming.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the ssh profile"
IMPL="$( impl )"
[ -n "$IMPL" ] || IMPL=openssh

case "$IMPL" in
    dropbear)
        # -R generates any host key that is missing, -p sets the port, -s turns
        # password logins off and -E logs to stderr rather than to a syslog
        # socket this container does not have. Public-key authentication reads
        # the same ~/.ssh/authorized_keys OpenSSH does, so a chain that
        # authorises a key on this host works whichever implementation was drawn.
        mkdir -p /etc/dropbear
        pkill -x dropbear 2>/dev/null
        i=25; while [ $i -gt 0 ] && pgrep -x dropbear >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
        dropbear -R -s -E -p "0.0.0.0:${port}" >/dev/null 2>&1 \
            || die "dropbear failed to start on $port"
        ;;
    *)
        # Host keys are generated at spawn rather than baked into the image, so
        # two containers in one range do not present the same key.
        ssh-keygen -A >/dev/null 2>&1
        # UsePAM is deliberately absent. This image's OpenSSH is built without
        # PAM, so the option is not merely ignored: sshd prints "Unsupported
        # option UsePAM" on every start, which put a warning in the middle of
        # every spawn's output for a setting that was already the effective
        # behaviour.
        cat > /etc/ssh/sshd_config <<CONF
Port $port
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
Subsystem sftp /usr/lib/ssh/sftp-server
CONF
        pkill -x sshd 2>/dev/null
        i=25; while [ $i -gt 0 ] && pgrep -x sshd >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
        /usr/sbin/sshd -f /etc/ssh/sshd_config || die "sshd failed to start on $port"
        ;;
esac
wait_listening tcp "$port" || die "the ssh service is not listening on $port"

# The identification string the server sends before the key exchange, which is
# what a banner grab and nmap's version detection both read:
# SSH-2.0-OpenSSH_9.6 or SSH-2.0-dropbear_2022.83.
ident="$( nc -w 3 127.0.0.1 "$port" </dev/null 2>/dev/null | head -1 | tr -d '\r' )"
ver="$( version_digits "${ident#SSH-2.0-}" )"
case "$IMPL" in
    dropbear) describe tcp "$port" ssh "$ver" ssh dropbear sshd ;;
    *)        describe tcp "$port" ssh "$ver" ssh openssh sshd ;;
esac
echo "profile ssh: up (${IMPL})"
