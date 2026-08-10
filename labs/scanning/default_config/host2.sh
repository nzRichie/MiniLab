#!/bin/bash
# host2: the host that runs nothing, at 104.1.0.42. Named for the container
# rather than for its role, so spawn.sh's output gives Part 2 away to nobody.
#
# It has an address, it answers ping, and nothing listens on it.
#
# It exists so that "the host is up" and "the host is worth attacking" are two
# different findings in this lab rather than one. A sweep of the /24 returns this
# address alongside the three service hosts, and only a port scan separates them:
# against this host nmap reports every scanned port closed, which looks nothing
# like a filtered host and nothing like a host running something.
#
# Nothing is started here on purpose. The container is run with an explicit
# command so the base image's sshd never starts, which would otherwise leave port
# 22 open on this host and on every other host in the lab.
set -e

ip address add 104.1.0.42/24 dev 104-S1 2>/dev/null || true
ip link set 104-S1 up
ip route add default via 104.1.0.1 2>/dev/null || true

# What this prints is streamed into the TUI's Spawn panel, so it names no
# address, port, service or account: the learner reads this before they have
# scanned anything, and all of that is what Parts 1 to 3 have them find.
echo "host2 configured"
