#!/bin/sh
# The TFTP server profile: tftp-hpa on udp/69.
#
# TFTP has no directory listing and no authentication. There is no command that
# says what is on the server, so a file is readable exactly when its name is
# already known, and learning the name is a separate piece of work somewhere else
# on the range: a module listing on the file-sync daemon, a page the web server's
# index does not link to, or a note on the document drop.
#
# What it holds is a configuration backup, which is what a network switch pushes
# to a TFTP server every night, and what a configuration backup holds is the
# running configuration including its credentials.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_udp )"
[ -n "$port" ] || die "no udp port drawn for the tftp profile"
FILENAME="$( param tftp_file )"
ACCOUNT="$( param tftp_account )"
PASSWORD="$( param tftp_password )"

ROOT=/srv/tftp
mkdir -p "$ROOT"
chmod 755 "$ROOT"

# A decoy and the real one look identical from outside: neither can be listed, so
# a learner who has one filename has one file.
cat > "$ROOT/README" <<NOTE
${ORG_NAME} configuration archive.
Nightly pushes from the switches. Filenames follow the site naming standard.
NOTE

if [ -n "$FILENAME" ]; then
    cat > "${ROOT}/${FILENAME}" <<CFG
!
! ${ORG_NAME} - running configuration archive
! pushed from $( hostname ) at $( org_site 1 )
!
hostname $( hostname )
!
service password-encryption
$( [ -n "$ACCOUNT" ] && printf 'username %s privilege 15 password 0 %s\n' "$ACCOUNT" "$PASSWORD" )
!
line vty 0 4
 transport input telnet
 login local
!
snmp-server community public RO
!
end
CFG
    chmod 644 "${ROOT}/${FILENAME}"
fi
chmod 644 "$ROOT/README"

pkill -x in.tftpd 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x in.tftpd >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
in.tftpd --listen --address "0.0.0.0:${port}" --secure "$ROOT" \
    || die "in.tftpd failed to start on udp/$port"
wait_listening udp "$port" || die "in.tftpd is not listening on udp/$port"

# TFTP carries no banner and no version: the first thing on the wire is the
# learner's own read request. There is nothing to record and nothing to grade.
describe udp "$port" tftp "" tftp tftpd

[ -n "$FILENAME" ] && intel tftp-file
echo "profile tftp: up"
