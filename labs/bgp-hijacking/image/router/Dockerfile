# Router image for the BGP prefix-hijacking lab. One image serves all six ASes;
# each boots the FRR routing suite and is configured entirely over vtysh, so a
# router is a pure control-plane device the learner never runs bash inside.
#
# Built FROM the published mini-internet host image (the same base the reflection
# lab uses), plus FRR. That base is Alpine 3.19; its FRR package is 9.1, which
# enforces `bgp ebgp-requires-policy` by default -- so every eBGP neighbour in
# default_config/ carries an explicit inbound and outbound route-map, matching the
# mini-internet's own "never a bare neighbour" practice.
FROM miniinterneteth/d_host:latest

# frr            : zebra + staticd + bgpd (zebra and staticd are mandatory daemons
#                  frrinit always starts; bgpd is opt-in, enabled just below).
# frr-rpki       : bgpd_rpki.so, the module that speaks RTR to a relying-party
#                  cache and stamps each route Valid, Invalid or NotFound. It is a
#                  separate package and pulls in rtrlib; without it `rpki` is not a
#                  command bgpd knows and Part 2 of this lab cannot run.
# frr-pythontools: pulls python3, which the status/selftest oracle uses INSIDE the
#                  container to parse `show ip bgp ... json` (keeps python off the host).
RUN apk add --no-cache frr frr-rpki frr-pythontools \
    && sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons \
    # A module is only available if bgpd is launched with -M. Editing bgpd_options
    # here means every router boots RPKI-capable, so the learner configures a cache
    # rather than restarting a daemon.
    && sed -i 's|^bgpd_options=.*|bgpd_options="  --daemon -A 127.0.0.1 -M rpki"|' /etc/frr/daemons \
    # Fail the build rather than a lab spawn if the module ever stops shipping.
    && test -f /usr/lib/frr/modules/bgpd_rpki.so

# Start FRR and hold PID 1. Replaces the base image's sshd CMD; the lab reaches
# every router with `docker exec`, so no sshd is needed here.
COPY start-frr /usr/local/bin/start-frr
RUN chmod 755 /usr/local/bin/start-frr
CMD ["/usr/local/bin/start-frr"]
