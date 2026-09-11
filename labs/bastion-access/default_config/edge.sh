#!/bin/sh
# Starter config for the edge router: the one device every packet between the
# three segments crosses.
#
# It arrives forwarding everything and filtering nothing, which is what makes
# Part 1's sweep reach machines it has no business reaching. Forwarding itself is
# turned on at `docker run` with --sysctl, not here: Docker mounts /proc/sys
# read-only in an unprivileged container, and making the router privileged just
# to write one sysctl is more privilege than this lab needs.
#
# It runs no sshd. Nothing in this lab logs in to the router, and a listener here
# would put a service on port 22 of an address every sweep in Part 1 and Part 2
# is read for.
set -eu

PREFIXLEN=24
EDGE_EXT_IP="114.0.0.1"
EDGE_DMZ_IP="114.1.0.1"
EDGE_INNER_IP="114.2.0.1"

# Three interfaces, each named after the segment it faces. All three subnets are
# directly connected, so the router needs no route statement of its own: the
# kernel installs one per address.
ip addr replace "${EDGE_EXT_IP}/${PREFIXLEN}"   dev ext
ip link set ext up
ip addr replace "${EDGE_DMZ_IP}/${PREFIXLEN}"   dev dmz
ip link set dmz up
ip addr replace "${EDGE_INNER_IP}/${PREFIXLEN}" dev inner
ip link set inner up

# Throw away any ruleset a previous run of the lab left behind. Deleting every
# table leaves the forward hook with no base chain at all, which is the kernel's
# own starting point and is what "filters nothing" means: with no chain
# registered at a hook, nothing is examined and nothing is dropped.
nft flush ruleset 2>/dev/null || true

echo "edge: three segments addressed, forwarding on, no packet filter"
