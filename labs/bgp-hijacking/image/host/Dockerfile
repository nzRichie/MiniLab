# Host image for the BGP prefix-hijacking lab. One image serves every host role:
#   * victim   (AS1)  serves the identity banner on 1.0.0.1  -> "AS1: legitimate"
#   * attacker (AS6)  serves an impostor banner on the same 1.0.0.1 and stands up
#                     the /25 impostor slice locally
#   * client   (AS2-AS5) the measurement vantages: curl + traceroute the service IP
# Hosts are the bash side of the lab; the routers stay pure vtysh. This image also
# doubles as the privileged wiring helper (it ships full iproute2 for veth/netns).
FROM miniinterneteth/d_host:latest

# iproute2  : a full `ip` (the base ships only BusyBox's applet, which cannot do
#             `ip link add type veth` / `ip netns exec` -- needed by the helper).
# curl      : the data-plane oracle (curl the service IP, read who answered).
# traceroute: shows the forwarding path bending toward the attacker after a hijack.
# python3   : runs the one-line banner HTTP server (reliable across repeat requests).
RUN apk add --no-cache iproute2 curl traceroute python3

# The identity banner server: binds 0.0.0.0:80 and answers every GET with a fixed
# line. Takes the identity string as its only argument, so victim and attacker
# name their own; nothing is defaulted.
COPY banner-server /usr/local/bin/banner-server
RUN chmod 755 /usr/local/bin/banner-server
