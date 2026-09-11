#!/bin/sh
# The host that runs nothing.
#
# It has an address and it is on the network, and no process is listening on any
# port. Every range holds exactly one, and where the shape gives the attacker a
# segment of its own it is the host on that segment: an ARP request finds it, an
# echo request does not, and a port scan reports nothing open.
#
# It exists so that "this address holds a host" and "this address holds
# something worth probing further" are two different findings on this range
# rather than one. It scores as a host and contributes no ports, no service and
# no version, so a learner who reports a service on it loses a mark.
set -u
. /etc/minilabs/profiles/_lib.sh

# Nothing to start, so nothing to confirm and no descriptor to write. The
# directories _lib.sh created are the whole of this profile's output: an empty
# profile.d is what score.sh reads as "no open port here".
echo "profile none: no service"
