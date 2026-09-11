#!/bin/sh
# Starter config for ZURI, applied by spawn.sh and re-applied by reset.sh.
#
# ZURI arrives with NOTHING configured, because configuring it is the lab. Its
# interfaces exist and are up (spawn.sh renamed and raised them when it moved each
# veth end in), and FRR is running with zebra and ospfd, but no interface carries
# an address, the loopback carries no address, and there is no `router ospf`
# stanza at all. Every address in this lab is one the learner types.
#
# Addresses this router ENDS UP with, for reference (from scripts/lib.sh, which
# this script cannot source because it runs inside the container):
#   port_NEWY    109.0.2.2/30   (toward NEWY)
#   port_TRGA    109.0.3.2/30   (toward TRGA)
#   host         109.105.0.2/24   (toward its own host)
#   lo           109.155.0.1/32   (loopback, also the router-id)
#
# Run twice, this leaves the router in exactly the same state, which is what makes
# it usable as the undo button.
#
# Blanking works by restarting FRR against an empty frr.conf rather than by
# unpicking whatever the learner typed, so it does not need to know which commands
# those were. That restart is only fast because the container runs with docker's
# --init: FRR stops a daemon by sending SIGINT and then polling `kill -0` for up
# to 120 seconds, and with `sleep infinity` as PID 1 nothing reaps the exited
# daemon, so `kill -0` keeps succeeding against a zombie and every stop takes the
# full two minutes. With an init process reaping, the same stop returns at once.
set -u

LAB_IFS="port_NEWY port_TRGA host"

# 1. Blank FRR. An empty frr.conf plus a restart removes the OSPF stanza, every
#    interface stanza, every cost and every authentication key in one step.
cat > /etc/frr/frr.conf <<'FRRCONF'
frr defaults traditional
log syslog informational
service integrated-vtysh-config
line vty
FRRCONF
chown frr:frr /etc/frr/frr.conf
chmod 640 /etc/frr/frr.conf

/usr/lib/frr/frrinit.sh restart >/dev/null 2>&1 || true

# 2. Hold until vtysh answers again, so spawn.sh and reset.sh never hand a router
#    back to the learner before it can take a command.
i=0
ready=0
while [ $i -lt 60 ]; do
    if vtysh -c 'show version' >/dev/null 2>&1; then ready=1; break; fi
    i=$(( i + 1 ))
    sleep 0.5
done
if [ $ready -ne 1 ]; then
    echo "FRR did not come back up on zuri" >&2
    exit 1
fi

# 3. Drop any address left on a lab interface. zebra removes the addresses it
#    installed when it shuts down, so after the restart there is usually nothing
#    here to remove; this catches an address that outlived it and an address that
#    was never FRR's to begin with. `scope global` is what keeps 127.0.0.1 on lo
#    while removing a loopback address configured for OSPF, which sits in global
#    scope like any other.
for i in $LAB_IFS lo; do
    ip -4 addr flush dev "$i" scope global 2>/dev/null || true
done

exit 0
