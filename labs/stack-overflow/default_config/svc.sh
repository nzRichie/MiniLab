#!/bin/sh
# Starter configuration for the appliance.
#
# It arrives with the vulnerable build running and nothing else: no hardened
# binary on disk, no empty log, and the service already listening. Everything
# Part 2 produces is written by the learner.
#
# reset.sh re-runs this script, so it has to be able to undo whatever a learner
# left behind. That is why it recompiles the vulnerable build from the source
# rather than trusting the copy in the image: a learner working through Part 2
# may have overwritten it, and a lab that came back from Reset running a
# hardened binary under the vulnerable binary's name would make every later
# observation wrong.
set -e

IF="121-lan"
ADDR="121.0.0.10/24"

SRC="/opt/devreg/src/devregd.c"
SRC_PRISTINE="/usr/local/share/minilabs/devregd.c"
BIN_DIR="/opt/devreg/bin"
PLAIN="$BIN_DIR/devregd"
LOG="/var/log/devregd.log"
PORT=9000

ip addr flush dev "$IF" 2>/dev/null || true
ip addr add "$ADDR" dev "$IF"
ip link set dev "$IF" up

# Stop whatever build is running. pkill is the container's direct command here,
# not wrapped in a shell whose own command line would match the pattern.
pkill -f "$BIN_DIR/" >/dev/null 2>&1 || true
sleep 0.3

# The source, restored. Mode 0444 says do not edit it, but every shell in this
# lab is root and root ignores the mode, so the copy is what actually holds the
# invariant that the program the handout describes is the program on the
# appliance. A learner who edited it gets the original back from Reset.
cp -f "$SRC_PRISTINE" "$SRC"
chmod 444 "$SRC"

# Everything Part 2 wrote, removed. The pristine build is the one the image
# compiled; recompiling it here with the same flags rather than copying it keeps
# one command line for this build instead of two things that have to agree.
rm -f "$BIN_DIR"/devregd-*
gcc -O0 -fno-stack-protector -no-pie -o "$PLAIN" "$SRC"
chmod 755 "$PLAIN"

: > "$LOG"
chmod 644 "$LOG"

# setarch -R clears address-space randomisation for this process and its
# children. It is not the same as writing kernel.randomize_va_space, which is
# global to the machine and not writable from a container at all. The vulnerable
# build is not position-independent, so its own addresses do not move either
# way; the flag is here so that every build in this lab is started the same way
# and Part 2C's comparison is between the binaries and not between how they were
# launched.
setsid setarch -R "$PLAIN" "$PORT" >>"$LOG" 2>&1 </dev/null &

sleep 0.5
echo "svc: $ADDR on $IF, devregd listening on $PORT"
