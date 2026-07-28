# Host image for the VLAN-hopping lab.
# One image serves every host role on top of the stock mini-internet host image
# (which already ships tcpdump, nmap/nping, ping, dig, iperf3):
#   * attacker  crafts the double-tagged frame with scapy, and tries the simpler
#               single-tag injection with a Linux 802.1Q subinterface (iproute2)
#   * peer      a plain VLAN 10 host, the attacker's honest same-VLAN reach
#   * victim    a plain VLAN 20 host; captures what lands on it (the hop oracle)
# The switches run the stock miniinterneteth/d_switch image unchanged; all VLAN
# tagging is OVS port config, not host software.
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip`, including `ip link add ... type vlan` for the
# single-tag injection attempt (the base image's BusyBox `ip` cannot add VLAN
# subinterfaces). scapy (pulls python3) crafts the double-tagged frame, tag by tag.
RUN apk add --no-cache iproute2 scapy

# The one-command baseline double-tagging tool. The handout drives the attack by
# hand (raw scapy, every field typed out); this exists as the scripted equivalent
# and takes NO defaults for the VLAN ids or the target, so running it still means
# naming the outer (native) VLAN, the inner (victim) VLAN, and the target address.
COPY vlan-double-tag /usr/local/bin/vlan-double-tag
RUN chmod 755 /usr/local/bin/vlan-double-tag
