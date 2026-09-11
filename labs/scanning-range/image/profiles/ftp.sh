#!/bin/sh
# The FTP service profile: vsftpd, on one drawn port.
#
# Exactly one FTP service in a range accepts an anonymous login. That one holds
# an operations handover note naming an account used on a telnet host elsewhere,
# so enumerating it is what supplies the username the dictionary attack needs.
# Every other FTP service in the range asks for a login it will not get, which is
# what stops a range with three FTP hosts being three free findings.
set -u
. /etc/minilabs/profiles/_lib.sh

ANON="$( param ftp_anon no )"
ACCOUNT="$( param leak_account )"
KEY_PASSPHRASE="$( param key_passphrase )"
DECOY_FLAG="$( param decoy_flag )"
port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the ftp profile"

FTP_ROOT=/var/lib/ftp
mkdir -p "$FTP_ROOT/pub"

if [ "$ANON" = yes ]; then
    cat > "$FTP_ROOT/pub/handover.txt" <<NOTE
${ORG_NAME} - ${ORG_TEAM} handover
----------------------------------------------
Left by the outgoing contractor. Whoever picks this up, please work through it.

 * This document drop still allows anonymous FTP. It was set up that way so the
   ${ORG_DROP} could be dropped without accounts, and it was meant to be
   temporary. It should be closed.

 * Remote administration on the network equipment is still plain telnet, not
   SSH. Everyone in ${ORG_TEAM} shares the '${ACCOUNT}' account on those boxes.
   Moving them to SSH with per-user keys has been on the list for a long time.

 * The password on that account has not been rotated since the account was
   created, and it is not written down anywhere, so ask around before you lock
   yourself out.

 * Sites still on the old addressing: $( org_site 1 ), $( org_site 2 ).
NOTE
    chmod 644 "$FTP_ROOT/pub/handover.txt"

    # One half of the vault's key. The key file itself is on the telnet host,
    # behind a login; this is the passphrase that decrypts it, and it is sitting
    # on a share that needs no login at all. Two different pieces of work reach
    # the two halves, which is what stops the chain being a single corridor: a
    # learner who cracked the telnet account and never enumerated this share has
    # a key they cannot use.
    if [ -n "$KEY_PASSPHRASE" ]; then
        cat > "$FTP_ROOT/pub/backup-runbook.txt" <<RUNBOOK
${ORG_NAME} - overnight backup runbook
-------------------------------------------
The offsite backup box is not on the general network. It sits on its own segment
and the router only lets the jump host talk to it, so run this from there and
nowhere else.

  ssh -i ~/.ssh/id_ed25519 ${CHAIN_ACCOUNT:-svc-backup}@<backup box>

The key is on the jump host under the service account, not in this drop. Its
passphrase is:

  ${KEY_PASSPHRASE}

Yes, the passphrase is written down in the same place as the runbook. It was
supposed to move into the password manager when we got one.
RUNBOOK
        chmod 644 "$FTP_ROOT/pub/backup-runbook.txt"
    fi

    # The decoy token. It is shaped exactly like a real one and it belongs to a
    # rebuild that never finished, which the file says in its first line. It
    # matches no milestone this range planted, so submitting it scores nothing
    # and costs nothing; reading the two lines around it is what a learner is
    # being rewarded for.
    if [ -n "$DECOY_FLAG" ]; then
        cat > "$FTP_ROOT/pub/staging-rebuild.txt" <<DECOY
${ORG_NAME} - staging rebuild, abandoned
-----------------------------------------
This is the old staging environment's paperwork. The rebuild was cancelled and
the environment was torn down; nothing in here refers to anything that is still
running. Kept only because nobody was sure it was safe to delete.

Last capture-the-flag exercise token from that environment:

  ${DECOY_FLAG}

The environment it came from no longer exists.
DECOY
        chmod 644 "$FTP_ROOT/pub/staging-rebuild.txt"
    fi
fi

# vsftpd refuses to start if the anonymous root is writable by the user it
# chroots into, so the directory is left read-only on purpose.
chown -R root:root "$FTP_ROOT"
chmod 555 "$FTP_ROOT"
chmod 755 "$FTP_ROOT/pub"

conf=/etc/vsftpd/vsftpd-lab.conf
cat > "$conf" <<CONF
listen=YES
listen_port=$port
listen_ipv6=NO
anonymous_enable=$( [ "$ANON" = yes ] && echo YES || echo NO )
# One of local_enable and anonymous_enable has to be YES or vsftpd answers every
# connection with "500 OOPS: vsftpd: both local and anonymous access disabled!"
# and closes it, which is not a service that refuses a login, it is a service
# that is broken. A non-anonymous share therefore accepts local logins and holds
# one account whose password is not in the range's wordlist, so it greets
# normally, identifies itself, and gives up nothing.
local_enable=$( [ "$ANON" = yes ] && echo NO || echo YES )
write_enable=NO
anon_upload_enable=NO
anon_mkdir_write_enable=NO
no_anon_password=YES
anon_root=$FTP_ROOT
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=NO
pasv_enable=YES
pasv_min_port=${FTP_PASV_MIN:-30000}
pasv_max_port=${FTP_PASV_MAX:-30100}
seccomp_sandbox=NO
background=YES
secure_chroot_dir=/var/lib/vsftpd/empty
CONF
if [ "$ANON" != yes ]; then
    id ftpsvc >/dev/null 2>&1 || adduser -D -H -s /sbin/nologin ftpsvc
    # Long, and deliberately not a word from /usr/share/minilabs/passwords.txt:
    # this account is here so the service has something to refuse, not so it can
    # be guessed. The dictionary attack in this range is against telnet.
    echo 'ftpsvc:Xq7-tundra-9142-bracket-Vy' | chpasswd >/dev/null 2>&1
fi

mkdir -p /var/lib/vsftpd/empty
# The mode is set explicitly rather than left to the ambient umask. vsftpd
# chroots its pre-authentication process into secure_chroot_dir and refuses every
# session with "500 OOPS: refusing to run with writable root inside chroot()" if
# that directory is writable. `docker exec` runs with umask 0022 under a rootful
# daemon but 0000 under a rootless one, where mkdir would leave it 777.
chmod 755 /var/lib/vsftpd /var/lib/vsftpd/empty

pkill -x vsftpd 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x vsftpd >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
vsftpd "$conf" || die "vsftpd failed to start on $port"
wait_listening tcp "$port" || die "vsftpd is not listening on $port"

# The 220 greeting names the software and its version, which is what a banner
# grab and nmap's version detection both read. Recording it from the greeting
# rather than from the package database keeps the two the same string.
greeting="$( printf 'QUIT\r\n' | nc -w 3 127.0.0.1 "$port" 2>/dev/null | head -1 )"
# The leading three-digit reply code is stripped before the version is read out.
# Without that step version_digits returns the first number in the line, which is
# the 220 of the greeting itself, and every learner who correctly reported
# "3.0.5" would have been marked wrong against a ground truth of "220".
describe tcp "$port" ftp "$( version_digits "$( echo "$greeting" | sed 's/^[0-9][0-9][0-9][ -]*//' )" )" ftp vsftpd

if [ "$ANON" = yes ]; then
    intel anon-ftp
    [ -n "$ACCOUNT" ] && intel leaked-account
    [ -n "$KEY_PASSPHRASE" ] && intel leaked-passphrase
fi
echo "profile ftp: up"
