#!/bin/sh
# The log collector profile: a UDP sink on 514 that answers nothing, ever.
#
# It is the open-versus-filtered lesson in one port. UDP has no handshake, so a
# datagram sent to a port where something is listening and choosing not to reply
# looks exactly like a datagram sent to a port a firewall dropped: nothing comes
# back either way. `nmap -sU` reports both as `open|filtered`, and the state is
# named that way because the scanner genuinely cannot tell which it is.
#
# What separates them is the ports around it. A closed UDP port on a host that
# refuses rather than drops answers with an ICMP port unreachable, so a host that
# reports `closed` on its other UDP ports and `open|filtered` on this one is
# telling a learner that something IS bound here. That is why this profile is
# only ever placed on a host that refuses its shut ports: on a host that drops
# them, every port reads the same and the comparison the lesson turns on is gone.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_udp )"
[ -n "$port" ] || die "no udp port drawn for the syslog profile"

mkdir -p /var/log/collected
pkill -f "UDP4-RECV:${port}" 2>/dev/null
socat -u "UDP4-RECV:${port},reuseaddr" \
    "OPEN:/var/log/collected/messages,creat,append" >/dev/null 2>&1 &
wait_listening udp "$port" || die "the log collector is not listening on udp/$port"

describe udp "$port" syslog "" syslog syslogd rsyslog log

echo "profile syslog: up"
