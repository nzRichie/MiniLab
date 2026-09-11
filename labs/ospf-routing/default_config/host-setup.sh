#!/bin/sh
# Starter config for every host, applied by spawn.sh and re-applied by reset.sh.
#
#   host-setup.sh <own-address/prefix> <gateway> <banner text>
#
# A host arrives with its own address on its `router` interface and NO default
# route. Adding that route is a step of the lab, and until it is added the host
# reaches its own subnet and nothing else. The gateway is passed in only so the
# script can remove a default route pointing at it; the script never adds one.
#
# The banner server is the lab's data-plane oracle: each host serves its own name
# on port 80 of its own address, so a curl that crosses the network reports which
# host actually received the request.
#
# Run twice, this leaves the host in exactly the same state, which is what makes
# it usable as the undo button.
set -u

ADDR="$1"          # e.g. 109.101.0.1/24
GW="$2"            # e.g. 109.101.0.2
BANNER="$3"

IF=router

# 1. Stop the banner server and WAIT for it to let go of port 80. A signalled
#    process still holds its listening socket until it actually exits, so starting
#    the replacement without waiting fails on "Address in use" perhaps one run in
#    three. Started again at the end, once addressing is back to what it should be.
pkill -f banner-server >/dev/null 2>&1 || true
i=0
while [ $i -lt 40 ]; do
    pgrep -f banner-server >/dev/null 2>&1 || break
    i=$(( i + 1 ))
    sleep 0.25
done
pkill -KILL -f banner-server >/dev/null 2>&1 || true

# 2. Addressing. `flush ... scope global` clears both this host's own address and
#    anything extra a learner added, on the interface and on the loopback, without
#    disturbing 127.0.0.1.
ip -4 addr flush dev "$IF" scope global 2>/dev/null || true
ip -4 addr flush dev lo scope global 2>/dev/null || true
ip address replace "$ADDR" dev "$IF"
ip link set dev "$IF" up

# 3. No default route: adding one is the learner's job. Removing whatever is there
#    covers both a re-run and a learner who pointed it somewhere wrong.
ip route del default >/dev/null 2>&1 || true
ip route del default via "$GW" >/dev/null 2>&1 || true

# 4. This host's own identity, bound to its own address rather than to every
#    address, so the reply a curl gets names the machine that received it.
setsid /usr/local/bin/banner-server "${ADDR%%/*}" "$BANNER" >/dev/null 2>&1 &

# The server needs to be listening before spawn.sh reports the lab up, so give it
# a moment and confirm rather than assume.
i=0
while [ $i -lt 20 ]; do
    if curl -s --max-time 1 "http://${ADDR%%/*}/" >/dev/null 2>&1; then exit 0; fi
    i=$(( i + 1 ))
    sleep 0.25
done
echo "banner server did not start on ${ADDR%%/*}" >&2
exit 1
