#!/bin/sh
# Starter config for the router: address the three legs, hang the two shapers
# off them, and forward everything. No filtering and no source checking at all,
# because writing those is Part 2 and a defence that is already on is not a
# defence the learner applied.
#
# ip_forward is already 1 and rp_filter is already 0 on `all` and `default`,
# both set at `docker run`: a fresh container on most hosts inherits
# rp_filter=1, which would leave Stage 1's "turn the check on" step a no-op on
# some machines and not others.
set -eu

R_INSIDE_IP="129.0.0.1"
R_FIELD_IP="129.1.0.1"
R_OP_IP="129.2.0.1"
PREFIXLEN=24
IF_INSIDE="129-S1"
IF_FIELD="129-S2"
IF_OP="129-S3"

# The asymmetric access link this whole lab is measured against: 1 Mbit/s toward
# the victim, 256 kbit/s away from it.
DOWN_RATE="1mbit";   DOWN_BURST="32kbit"; DOWN_LATENCY="50ms"
# The burst is the bucket size, and a packet bigger than the bucket is dropped
# rather than delayed, so it must be at least one MTU: 16kbit is 2000 bytes.
UP_RATE="256kbit";   UP_BURST="16kbit";   UP_LATENCY="50ms"

# --- addressing -----------------------------------------------------------
ip addr replace "${R_INSIDE_IP}/${PREFIXLEN}" dev "$IF_INSIDE"
ip addr replace "${R_FIELD_IP}/${PREFIXLEN}"  dev "$IF_FIELD"
ip addr replace "${R_OP_IP}/${PREFIXLEN}"     dev "$IF_OP"
ip link set "$IF_INSIDE" up
ip link set "$IF_FIELD" up
ip link set "$IF_OP" up

# Every leg is directly connected, so the router needs no routes beyond the
# three the addresses give it.

# --- the bottleneck -------------------------------------------------------
#
# One token bucket per direction. The downlink shaper sits on the inside egress,
# so it meters everything arriving for the victim; the uplink shaper sits on the
# field egress, so it meters everything the victim sends out. A qdisc only ever
# shapes what LEAVES the interface it is attached to, which is why there are two
# of them and why neither is on the victim's own interface: a filter the learner
# writes here sits upstream of the congestion, which is where scrubbing happens
# in the real case.
#
# `del` then `add` rather than `replace`. Replacing a qdisc keeps its
# statistics, and every reading in this lab is a drop count read from a known
# zero.
for dev_rate in "$IF_INSIDE $DOWN_RATE $DOWN_BURST $DOWN_LATENCY" \
                "$IF_FIELD $UP_RATE $UP_BURST $UP_LATENCY"; do
    # shellcheck disable=SC2086
    set -- $dev_rate
    tc qdisc del dev "$1" root 2>/dev/null || true
    tc qdisc add dev "$1" root tbf rate "$2" burst "$3" latency "$4"
done

# --- no policy, no source checking ----------------------------------------
# A learner's rules live in the FORWARD chain of the filter table; flushing it
# and setting the policy back to ACCEPT is what makes reset.sh return the router
# to an open forwarder. The nat and mangle tables are never touched by this lab.
iptables -F FORWARD 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true

# Strict uRPF off on every interface, and no martian logging. Both are Stage 1's
# first mitigation, so a reset has to put them back.
for i in "$IF_INSIDE" "$IF_FIELD" "$IF_OP"; do
    sysctl -qw "net.ipv4.conf.${i}.rp_filter=0"
    sysctl -qw "net.ipv4.conf.${i}.log_martians=0"
done

echo "router: three legs addressed, forwarding on, FORWARD chain open, uRPF off"
echo "router: ${DOWN_RATE} toward the victim on ${IF_INSIDE}, ${UP_RATE} away from it on ${IF_FIELD}"
