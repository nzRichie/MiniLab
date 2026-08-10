# Host image for the MAC-flooding lab.
# One image serves every host role on top of the stock mini-internet host image
# (which already ships tcpdump, nmap/nping, ping, dig, iperf3):
#   * attacker  floods S1's MAC table from random source addresses, and captures
#               the victim-to-gateway frames the switch then floods to every port
#   * victim    an ordinary host on the same access switch; its traffic to the
#               gateway is what leaks
#   * gateway   the far end of that path, behind the uplink
#   * staff     ten interfaces standing in for ten machines behind the uplink;
#               their addresses are the reason the uplink carries more than its
#               fair share of the table
# The switches run the stock miniinterneteth/d_switch image unchanged: every
# MAC-table setting in this lab is OVS bridge and port config, not host software.
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip`; the base image's BusyBox applet cannot report
# per-interface addresses the way the staff container's ten NICs need. scapy
# (which pulls python3) is what builds the first flood frames by hand, field by
# field, before the learner turns the sustained flood on.
RUN apk add --no-cache iproute2 scapy iputils-arping

# The sustained flood. The handout has the learner build and send the first frames
# in scapy, so they type out the one field that matters (a source address the
# switch has never seen), and this exists for the part that follows, where the
# flood has to be held open for as long as the measurement runs. scapy sends a few
# hundred frames a second; filling a table and holding it full needs thousands, so
# this writes them straight to a packet socket.
#
# It takes NO defaults: running it still means naming the interface to flood, how
# many frames to send, and how fast.
COPY mac-flood /usr/local/bin/mac-flood
RUN chmod 755 /usr/local/bin/mac-flood
