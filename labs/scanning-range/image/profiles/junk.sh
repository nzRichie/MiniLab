#!/bin/sh
# Junk listeners: open ports with nothing behind them.
#
# The `noisy` mutator draws this onto a few hosts. Each port accepts a connection
# and then says nothing at all, so a scanner reports it open, version detection
# reports no product, and every minute spent on it is a minute not spent on the
# services that lead somewhere. Judging that an open port is not worth another
# probe is the skill; there is nothing here to find.
#
# The descriptor says so out loud: the service name is `unknown`, which is what a
# learner should submit for a port they could not identify, and it is what the
# scorer accepts.
set -u
. /etc/minilabs/profiles/_lib.sh

opened=0
for port in $( ports_of_proto tcp ); do
    pkill -f "TCP4-LISTEN:${port}" 2>/dev/null
    # A listener that accepts and then blocks on a read that never returns. The
    # connection is established and the port is open; no byte is ever sent.
    socat "TCP4-LISTEN:${port},reuseaddr,fork" "OPEN:/dev/null" >/dev/null 2>&1 &
    if wait_listening tcp "$port" 20; then
        describe tcp "$port" unknown "" unknown tcpwrapped none
        opened=$(( opened + 1 ))
    fi
done
[ "$opened" -gt 0 ] || die "no junk listener came up"
echo "profile junk: ${opened} listener(s)"
