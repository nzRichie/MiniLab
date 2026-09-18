#!/bin/sh
# Starter config for the c2: the operator's own machine, where the learner runs
# the controller.
#
# It starts NOTHING. The controller is a program the learner runs (`c2` opens
# the console; the lifecycle scripts drive it with `c2 -c`), because starting it
# by hand and watching the population register against it is the exercise. This
# script only addresses the container and gives it the two addresses the
# rendezvous set resolves to.
#
# TWO addresses, on one container. The bot's candidate set holds eight
# operator-leg addresses; two of them are this machine and six are assigned to
# nothing. That is what Part 4's fourth move is built on: a learner who blocks
# the address they started the controller on is correct, and the population
# comes back through the second one inside one rendezvous pass. Both live here
# from spawn, because the whole point is that the fallback already exists and
# the learner did not know to block it.
set -eu

C2_IP="128.2.0.10"
C2_ALT_IP="128.2.0.58"
PREFIXLEN=24
OP_IF="128-S3"
OP_GW="128.2.0.1"

C2_DIR="/var/lib/c2"

# --- addressing -----------------------------------------------------------
ip addr replace "${C2_IP}/${PREFIXLEN}"     dev "$OP_IF"
ip addr replace "${C2_ALT_IP}/${PREFIXLEN}" dev "$OP_IF"
ip link set "$OP_IF" up
ip route replace default via "$OP_GW"

# --- clean controller state ----------------------------------------------
# A reset re-runs this file, so it clears whatever a previous session's
# controller left: the roster, the results, the standing task, and the control
# socket. It does NOT start a controller. If one is running (the learner started
# it), it is stopped so the next `c2` starts from an empty population, which is
# what the oracle's baseline counts assume.
if [ -f /run/minilabs/c2.pid ]; then
    kill "$( cat /run/minilabs/c2.pid )" 2>/dev/null || true
fi
# Fallback: any c2 process not covered by the pidfile. Matched on the full
# argument, not the name `python3`, so an instrument written in python is never
# caught by it.
pkill -f '/usr/local/bin/c2' 2>/dev/null || true

rm -rf "$C2_DIR"
mkdir -p "$C2_DIR/results"
chmod -R 755 "$C2_DIR"
rm -f /run/minilabs/c2.ctl /run/minilabs/c2.pid /var/log/c2.log

echo "c2: ${C2_IP} and ${C2_ALT_IP} addressed; no controller running (start it with: c2)"
