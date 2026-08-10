# Host image for the STP root-bridge-takeover lab.
# One image serves every host role on top of the stock mini-internet host image
# (which already ships tcpdump, nmap/nping, ping, dig, iperf3):
#   * attacker  forges Configuration BPDUs with scapy, and in Part 2 bridges its
#               two NICs together with iproute2 so the traffic it has pulled onto
#               itself still reaches the far side
#   * victim    an ordinary host; its ping to the gateway is what the outage and
#               the interception are measured against
#   * gateway   the far end of that path
# The switches run the stock miniinterneteth/d_switch image unchanged: every
# spanning-tree setting in this lab is OVS bridge and port config, not host
# software.
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip` and the `bridge` utility. The base image's BusyBox
# `ip` cannot create a bridge device (`ip link add ... type bridge`) or report
# per-port bridge state, and Part 2 needs both. scapy (which pulls python3) is
# what crafts the BPDU field by field.
RUN apk add --no-cache iproute2 scapy

# The one-command sustained root claim. The handout builds the first BPDU by hand
# in scapy, so the learner types out every field that decides the election; this
# exists for the part that follows, where the claim has to keep being made once
# per hello interval for as long as the attack runs. It takes NO defaults, so
# running it still means naming the interfaces, the priority and the bridge MAC
# the claim is made with.
COPY stp-root-claim /usr/local/bin/stp-root-claim
RUN chmod 755 /usr/local/bin/stp-root-claim
