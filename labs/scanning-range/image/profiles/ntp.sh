#!/bin/sh
# The time service profile: chrony or openntpd on udp/123, drawn per host.
#
# It is here because it is what an infrastructure survey actually turns up. A
# time server answers a client on UDP and is otherwise silent, so it is a UDP
# port that is genuinely open and genuinely uninteresting: the finding is that it
# is there, and the judgement is that there is nothing behind it worth another
# probe. A range where every open port leads somewhere teaches the opposite.
#
# Neither implementation announces a release to an unauthenticated client. Remote
# runtime queries are what chrony's `cmdport` and OpenNTPD's control socket are
# for, and both are local-only by default, so a version is not on the wire and
# none is recorded.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_udp )"
[ -n "$port" ] || die "no udp port drawn for the ntp profile"
IMPL="$( impl )"
[ -n "$IMPL" ] || IMPL=chrony

case "$IMPL" in
    openntpd)
        cat > /etc/ntpd-lab.conf <<CONF
listen on 0.0.0.0
CONF
        pkill -x ntpd 2>/dev/null
        i=25; while [ $i -gt 0 ] && pgrep -x ntpd >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
        ntpd -f /etc/ntpd-lab.conf >/dev/null 2>&1 \
            || die "openntpd failed to start on udp/$port"
        ;;
    *)
        # -x is load-bearing in a container: without it chronyd calls adjtimex to
        # take control of the system clock, which needs CAP_SYS_TIME, and the
        # failure is logged on every start for a capability a lab host has no
        # reason to hand out. -x runs it as a server that never touches the
        # clock, which is exactly what this profile wants.
        cat > /etc/chrony-lab.conf <<CONF
allow all
port $port
local stratum 8
driftfile /var/lib/chrony/lab.drift
pidfile /run/chronyd-lab.pid
CONF
        mkdir -p /var/lib/chrony
        pkill -x chronyd 2>/dev/null
        i=25; while [ $i -gt 0 ] && pgrep -x chronyd >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
        chronyd -x -f /etc/chrony-lab.conf >/dev/null 2>&1 \
            || die "chronyd failed to start on udp/$port"
        ;;
esac
wait_listening udp "$port" || die "the time service is not listening on udp/$port"

describe udp "$port" ntp "" ntp "$IMPL" ntpd time

echo "profile ntp: up (${IMPL})"
