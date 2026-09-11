#!/bin/sh
# The telnet service profile: busybox telnetd behind the range's own login
# front-end, on one drawn port.
#
# Every telnet host claims a device family in its login prompt, and the seed
# gives it up to two independent weaknesses:
#
#  * default-cred      the account the family ships with is still in place. The
#                      field manual's table lists it, so a learner who reads the
#                      prompt confirms it in one login.
#  * weak-telnet-pass  the shared operations account the FTP handover note named
#                      is present, and its password is one of the fifty in the
#                      wordlist. That one is a dictionary attack and a wait.
#
# The protocol carries both the username and the password in cleartext either
# way, and a failed login costs an attacker nothing: the connection closes, and
# there is no lockout, no delay and no record kept.
set -u
. /etc/minilabs/profiles/_lib.sh

FAMILY="$( param family )"
DEFAULT_CRED="$( param default_cred )"
OPS_ACCOUNT="$( param ops_account )"
port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the telnet profile"

make_account() {   # <user>:<pass>
    _user="${1%%:*}"; _pass="${1#*:}"
    id "$_user" >/dev/null 2>&1 || adduser -D -s /bin/ash "$_user"
    echo "${_user}:${_pass}" | chpasswd >/dev/null 2>&1
    # The home directory is read out of the account database rather than assumed
    # to be /home/<user>. One device family ships a default on the root account,
    # whose home is /root, and building the path by hand wrote into a directory
    # that does not exist.
    _home="$( getent passwd "$_user" | cut -d: -f6 )"
    [ -n "$_home" ] || _home="/home/${_user}"
    mkdir -p "$_home"
    cat > "${_home}/upload-schedule.txt" <<NOTE
${ORG_NAME} - ${ORG_DROP} upload schedule
  Mon 0600  $( org_site 1 ) -> document drop
  Wed 0600  $( org_site 2 ) -> document drop
  Fri 0600  $( org_site 3 ) -> document drop
Contact ${ORG_TEAM} if an upload window is missed.
NOTE
    chown "${_user}:${_user}" "${_home}/upload-schedule.txt"
}

[ -n "$DEFAULT_CRED" ] && make_account "$DEFAULT_CRED"
[ -n "$OPS_ACCOUNT" ]  && make_account "$OPS_ACCOUNT"

# busybox telnetd, with the range's own one-shot login front-end instead of
# /bin/login. image/lab-login explains why: busybox login re-prompts three times
# on one connection, which desyncs hydra's telnet module permanently after the
# first wrong password. Closing the session on a failed login is also what the
# device this host stands in for really does.
pkill -x telnetd 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x telnetd >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
/usr/sbin/telnetd -l /usr/local/bin/lab-login -p "$port" || die "telnetd failed to start on $port"
wait_listening tcp "$port" || die "telnetd is not listening on $port"

# No version is recorded, and that is the truth about this service rather than a
# gap in the range: busybox telnetd announces no software name and no version
# number, and nmap's version detection reports the operating system family at
# best. The scorer awards no version marks for a port whose ground truth carries
# none, so nobody is marked wrong for a version that was never on the wire.
describe tcp "$port" telnet "" telnet telnetd

[ -n "$DEFAULT_CRED" ] && intel default-cred
[ -n "$OPS_ACCOUNT" ]  && intel weak-telnet-pass
echo "profile telnet: up (${FAMILY:-unnamed})"
