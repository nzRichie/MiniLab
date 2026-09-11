#!/bin/sh
# The key-value store profile: redis on tcp/6379, with no authentication.
#
# Redis binds every interface and requires no password unless it is told to, and
# a copy reachable from a network it was never meant to be on is one of the
# commonest findings there is. `redis-cli KEYS *` returns the whole keyspace to
# anybody who can open the socket, and what is in the keyspace is whatever the
# application put there.
#
# The keyspace here holds an operational note, which is what a job queue's
# scratch space actually accumulates. Where the seed drew it, one of the values
# is the passphrase on a private key or the password on a shared account: a
# secret in a cache is a secret, and a cache with no authentication in front of
# it is where secrets go to be read.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the redis profile"
SECRET="$( param redis_secret )"
SECRET_KIND="$( param redis_secret_kind )"

conf=/etc/redis-lab.conf
cat > "$conf" <<CONF
port $port
bind 0.0.0.0
protected-mode no
daemonize yes
save ""
appendonly no
pidfile /run/redis-lab.pid
logfile /var/log/redis-lab.log
CONF

pkill -x redis-server 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x redis-server >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
redis-server "$conf" >/dev/null 2>&1 || die "redis failed to start on $port"
wait_listening tcp "$port" || die "redis is not listening on $port"

R="redis-cli -h 127.0.0.1 -p $port"
$R flushall >/dev/null 2>&1
$R set site "$( org_site 1 )" >/dev/null 2>&1
$R set queue:name "${ORG_PREFIX}-jobs" >/dev/null 2>&1
$R set note "scratch space for the overnight job. do not use for anything that matters." >/dev/null 2>&1
case "$SECRET_KIND" in
    passphrase) $R set backup:keyphrase "$SECRET" >/dev/null 2>&1 ;;
    password)   $R set ops:password "$SECRET" >/dev/null 2>&1 ;;
    filename)   $R set backup:archive "$SECRET" >/dev/null 2>&1 ;;
esac

# The release is in the INFO reply, under redis_version, which is also where
# nmap's version detection reads it from.
ver="$( $R info server 2>/dev/null | sed -n 's/^redis_version:\([0-9.]*\).*/\1/p' | tr -d '\r' )"
describe tcp "$port" redis "$ver" redis redis-server

intel redis-open
echo "profile redis: up"
