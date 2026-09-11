#!/bin/sh
# The file-sync daemon profile: rsync in daemon mode on tcp/873.
#
# An rsync daemon serves named modules, and a module with `list = yes` and no
# `auth users` is readable by anybody who can reach the port. `rsync
# rsync://host/` returns the module list with its comments, and `rsync
# rsync://host/<module>/` returns the file listing, which is the directory
# listing TFTP does not have and the anonymous share does.
#
# What it holds is the backup share: a runbook, a file inventory, and on some
# ranges the passphrase on a key or the name of a file that is only readable
# elsewhere by name.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the rsync profile"
SECRET="$( param rsync_secret )"
SECRET_KIND="$( param rsync_secret_kind )"

ROOT=/srv/backup
mkdir -p "$ROOT"
cat > "$ROOT/inventory.txt" <<INV
${ORG_NAME} - overnight backup inventory
  $( org_site 1 )   configuration archive, nightly
  $( org_site 2 )   configuration archive, nightly
  $( org_site 3 )   configuration archive, weekly
Retention is 30 days. Restores go through ${ORG_TEAM}.
INV
case "$SECRET_KIND" in
    passphrase)
        cat > "$ROOT/restore-notes.txt" <<NOTE
${ORG_NAME} - restore notes

The offsite copy is pulled over SSH by the backup job, with a key held on the
jump host. The key is passphrase-protected and the passphrase is:

  ${SECRET}

Written here because the password manager project has not landed. Move it.
NOTE
        ;;
    filename)
        cat > "$ROOT/restore-notes.txt" <<NOTE
${ORG_NAME} - restore notes

Switch configurations are not in this share. They go straight to the TFTP
server, under the name the site standard gives them:

  ${SECRET}

There is no listing on TFTP, so the name is the only way to fetch one.
NOTE
        ;;
esac
chmod -R 644 "$ROOT"/*.txt 2>/dev/null
chmod 755 "$ROOT"

cat > /etc/rsyncd-lab.conf <<CONF
port = $port
use chroot = no
max connections = 8
pid file = /run/rsyncd-lab.pid
log file = /var/log/rsyncd-lab.log

[backup]
    path = $ROOT
    comment = ${ORG_NAME} overnight backup share
    read only = yes
    list = yes
CONF

pkill -x rsync 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x rsync >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
rsync --daemon --config=/etc/rsyncd-lab.conf || die "rsync failed to start on $port"
wait_listening tcp "$port" || die "rsync is not listening on $port"

# The greeting is @RSYNCD: <protocol version>, and that number is the protocol's,
# not the program's. nmap reports the same number, and it is the number on the
# wire, so it is the number the scorer holds.
greeting="$( printf '\n' | nc -w 3 127.0.0.1 "$port" 2>/dev/null | head -1 | tr -d '\r' )"
describe tcp "$port" rsync "$( version_digits "${greeting#@RSYNCD:}" )" rsync rsyncd

intel rsync-module
echo "profile rsync: up"
