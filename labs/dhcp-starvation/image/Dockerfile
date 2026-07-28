# Host image for the DHCP-starvation / rogue-DHCP lab.
# Adds the DHCP server, a DHCP client, and the Layer-2 attack tooling on top of
# the stock mini-internet host image (which already ships tcpdump, nmap/nping,
# ping, dig, iperf3, and busybox udhcpc).
#
# One image serves all three host roles, exactly as d_host_arp does:
#   * server   runs the legitimate ISC dhcpd (from dhcp-server)
#   * attacker runs dhcp-starve (below) to drain the pool, then a SECOND dhcpd it
#     configures itself as the rogue server
#   * victim   runs busybox udhcpc to lease an address the honest way
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip` (the base image only has BusyBox's applet). scapy
# (which pulls python3) backs the dhcp-starve flooder. dhcp-server is ISC dhcpd,
# used by BOTH the legitimate server and the learner's rogue server.
RUN apk add --no-cache iproute2 scapy dhcp-server \
    && mkdir -p /var/lib/dhcp \
    && touch /var/lib/dhcp/dhcpd.leases

# The starvation flooder: sends full DISCOVER/REQUEST handshakes with spoofed
# client MACs until the pool is empty. The handout drives it by hand (the learner
# supplies the interface); this baked-in copy keeps it one command.
COPY dhcp-starve /usr/local/bin/dhcp-starve
RUN chmod 755 /usr/local/bin/dhcp-starve
