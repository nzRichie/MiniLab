# The one image for every container in the OSPF routing lab.
#
# Routers and hosts run the SAME image and differ only in what is started inside
# them: a router runs FRR from birth (the CMD below), a host is started with
# `sleep infinity` overriding that CMD and never runs it. The image also doubles
# as the privileged wiring helper, which is why it needs a full iproute2.
#
# One image rather than two halves the first spawn and keeps one dependency list
# to maintain. A host carrying an unused FRR costs nothing at run time, because
# nothing on a host ever starts it.
#
# Built FROM the published mini-internet host image, the same base the other L3
# labs use. That base is Alpine 3.19; its FRR package is 9.1.
FROM miniinterneteth/d_host:latest

# frr            : zebra + staticd + ospfd. zebra, staticd and mgmtd are mandatory
#                  daemons frrinit always starts; ospfd is opt-in and enabled below.
# frr-pythontools: pulls python3, which every oracle in scripts/ uses INSIDE the
#                  container to parse `show ip ospf ... json` (keeps python off the host).
# iproute2       : a full `ip` and `tc`. The base ships only BusyBox's applet, which
#                  cannot do `ip link add type veth` (needed by the wiring helper)
#                  and has no `tc` at all (needed for the per-link netem delay).
# curl           : the data-plane oracle -- curl an address, read back which host
#                  replied.
RUN apk add --no-cache frr frr-pythontools iproute2 curl \
    && sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons \
    # Fail the build rather than a lab spawn if either tool ever stops shipping.
    && test -x /usr/lib/frr/ospfd \
    && test -x /sbin/tc

# The identity banner server: binds ONE address on port 80 and replies to every GET
# with a fixed line. Each host serves its own name, so a curl that crosses the
# network reports which host actually received the request. That is a stronger
# check than ping, which only says that something replied.
COPY banner-server /usr/local/bin/banner-server

# Start FRR and hold PID 1. Replaces the base image's sshd CMD; every container in
# this lab is reached with `docker exec`, so no sshd is needed. Hosts override this
# with `sleep infinity` at `docker run` time.
COPY start-frr /usr/local/bin/start-frr
RUN chmod 755 /usr/local/bin/start-frr /usr/local/bin/banner-server
CMD ["/usr/local/bin/start-frr"]
