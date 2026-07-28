# Host image for the source-spoofing / reflection lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships tcpdump, nmap/nping, ping, dig, iperf3):
#   * router  forwards between the two subnets and is where the learner writes the
#             BCP38 filter — nftables for the ACL, sysctl for uRPF (rp_filter)
#   * dns     runs dnsmasq serving one oversized TXT record (the amplifier)
#   * ntp     runs ntpsec answering mode-6 "readvar" (the post-monlist amplifier)
#   * attacker forges source addresses with nping (-S) and scapy, and crafts the
#             reflected DNS/NTP queries the reflectors bounce at the victim
#   * victim  the reflection target; captures what lands on it
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip` (the base image only has BusyBox's applet, which
# cannot set per-interface sysctls or read `ip -s`). scapy (pulls python3) crafts
# the spoofed reflection queries. nftables + iptables are the two ACL toolchains
# for the defence. dnsmasq and ntpsec are the two reflector daemons. bind-tools
# gives a full `dig` for measuring the amplified response.
RUN apk add --no-cache \
        iproute2 \
        scapy \
        nftables iptables \
        dnsmasq \
        ntpsec \
        bind-tools \
    && mkdir -p /var/lib/ntpsec

# The one-command baseline reflection tool. The handout drives the attack by hand
# (raw scapy, every field typed out); this exists as the scripted equivalent and
# takes NO defaults for the addresses, so running it still means naming the
# reflector, the protocol, and the source you are forging.
COPY reflect /usr/local/bin/reflect
RUN chmod 755 /usr/local/bin/reflect
