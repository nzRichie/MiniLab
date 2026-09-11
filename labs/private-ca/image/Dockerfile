# Host image for the private-CA web service lab.
# One image serves all three roles on top of the stock mini-internet host image
# (which already ships an OpenSSH server, netstat, tcpdump and ping):
#   * ca      runs the two-tier certificate authority: it issues and it records,
#             and it never serves anything over the network but SSH
#   * server  runs the web service the certificate is issued for
#   * client  fetches the site and decides whether to believe the certificate
FROM miniinterneteth/d_host:latest

# openssl is the whole lab on the CA and half of it on the client: it generates
# the keys, writes the signing requests, signs them, and prints the verify code
# every part of this lab is read by. The base image ships none, only the OpenSSH
# server that links against libssl.
#
# ca-certificates is what makes /usr/local/share/ca-certificates and
# update-ca-certificates exist. Without it the client has a trust bundle it
# cannot add a local anchor to, and Part 3's last step has nowhere to put the
# root certificate.
#
# lighttpd carries mod_openssl in the main package on Alpine (no separate
# lighttpd-openssl exists), so `lighttpd -v` reporting "(ssl)" is the check that
# this image can terminate TLS at all. curl is how the client fetches, and it
# matters that it is built against OpenSSL: it reads the same trust bundle the
# client's `openssl s_client -CAfile` is pointed at, so the two agree about what
# is trusted.
#
# openssh-client is absent from the base image, which carries the server only.
# Without it neither the server nor the client could scp a signing request to the
# CA or collect a certificate back.
#
# iproute2 gives a full `ip`; the base image's /sbin/ip is a symlink to busybox,
# whose applet has no `ip -o` output format, which the lifecycle scripts parse.
RUN apk add --no-cache \
        openssl ca-certificates \
        lighttpd curl \
        openssh-client \
        iproute2
