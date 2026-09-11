#!/bin/sh
# The throughput tester profile: iperf3 in server mode.
#
# It measures a link and it does nothing else. There is no data on it, no
# configuration, no account and no file. It is here so that "this port is open"
# and "this port is worth another twenty minutes" stay two different judgements:
# a survey that treats every open port as a lead is a survey that runs out of
# time before it runs out of ports.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the iperf profile"

pkill -x iperf3 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x iperf3 >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
iperf3 --server --port "$port" --daemon >/dev/null 2>&1 \
    || die "iperf3 failed to start on $port"
wait_listening tcp "$port" || die "iperf3 is not listening on $port"

# iperf3 sends nothing until a client has sent a cookie, so there is no banner
# and no version on the wire.
describe tcp "$port" iperf "" iperf iperf3

echo "profile iperf: up"
