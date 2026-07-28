# Attacker/host image for the ARP-hijacking lab.
# Adds the Layer-2 attack + detection tooling on top of the stock mini-internet
# host image (which already ships tcpdump, nmap/nping, ping, arp, dig, iperf3).
#
# The handout drives the attack by hand with `nping` (nmap's packet crafter, from
# the base image): the learner discovers the MACs and sends the forged ARP replies
# themselves. Alpine 3.19 packages no dsniff/arpspoof or ettercap; a small scapy
# poisoner (`arp-poison`, baked in below) is kept as a one-shot baseline.
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip` (the base image only has BusyBox's applet, which has
# no `ip neigh replace` — needed for the static-ARP defence). scapy pulls python3.
RUN apk add --no-cache iproute2 scapy arpwatch iputils-arping macchanger arp-scan

# The baseline one-shot ARP-poisoning MITM tool (arp-poison), plus arpwatch/arp-scan
# for the detection/discovery side. `scapy` pulls in python3.
COPY arp-poison /usr/local/bin/arp-poison
RUN chmod 755 /usr/local/bin/arp-poison
