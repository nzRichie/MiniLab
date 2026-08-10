# Host image for the internet-scanning lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships tcpdump, nmap/nping, ping, dig, wget):
#   * attacker  runs the three scanners (zmap, masscan, nmap) and the password
#               attack (hydra); the only host the learner types on
#   * router    forwards between the attacker's subnet and the scanned /24
#   * web       lighttpd, the HTTP service the learner banner-grabs
#   * ftp       vsftpd with anonymous login, the service that leaks the account name
#   * telnet    busybox telnetd, the service the learner brute-forces
#   * idle      no service at all; it answers ping and nothing else
FROM miniinterneteth/d_host:latest

# The base image carries the nmap binary but NOT its script library: /usr/share/
# nmap/scripts is empty there, so --script banner, ftp-anon, http-title and
# http-enum all fail with "did not match a category, filename, or directory".
# nmap-scripts is what makes every NSE step in this lab work.
#
# zmap and masscan are the two mass scanners the lab compares against nmap.
# hydra drives the telnet password attack. ncat, curl and the telnet client are
# how the learner confirms by hand what a scanner reported. iproute2 gives a full
# `ip` (the base image only has BusyBox's applet).
#
# lighttpd, vsftpd and busybox-extras (telnetd) are the three services. They are
# installed in every container because one image serves every role; which daemon
# actually runs is decided by that container's default_config script.
RUN apk add --no-cache \
        nmap-scripts nmap-ncat \
        iptables \
        zmap masscan hydra \
        iproute2 curl inetutils-telnet \
        lighttpd vsftpd busybox-extras \
    && mkdir -p /usr/share/minilabs \
# masscan dlopen()s the unversioned "libpcap.so", which Alpine ships only in
# libpcap-dev; the runtime package provides libpcap.so.1 alone. Without this
# symlink every masscan run dies with "failed to load libpcap shared library",
# and a symlink is a great deal smaller than pulling in the -dev package.
    && ln -sf /usr/lib/libpcap.so.1 /usr/lib/libpcap.so

# The password list hydra works through in Part 3. Fifty of the most common
# passwords in public breach corpora, which is what makes the attack a realistic
# one: no exploit is involved, only an account whose password appears on a list
# anybody can download. The account's real password is in here, deliberately not
# at the top, so the learner watches hydra work rather than hit it first try.
COPY passwords.txt /usr/share/minilabs/passwords.txt
RUN chmod 644 /usr/share/minilabs/passwords.txt

# The telnet service's login front-end, used instead of /bin/login. Its header
# explains why: busybox login re-prompts three times on one connection, which
# desyncs hydra's telnet module permanently after the first wrong password, so a
# brute force would report "0 valid password found" with the password sitting in
# the list. It authenticates against the real /etc/shadow entry.
COPY lab-login /usr/local/bin/lab-login
RUN chmod 755 /usr/local/bin/lab-login
