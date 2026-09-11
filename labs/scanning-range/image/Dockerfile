# Host image for the scanning practice range.
#
# One image serves every role, because which role a container plays is drawn from
# the seed and is not known when the image is built:
#   * attacker  runs the scanners (zmap, masscan, nmap), the password attack
#               (hydra) and the `report` command the learner records findings
#               with; the only host the learner types on
#   * routers   forward between the segments the seed drew, with static routes
#               spawn.sh writes from state/topology.env
#   * hosts     run whichever service profile the seed drew for them, or nothing
#
# It is this range's own image and is built from this directory alone. It is a
# near copy of the fixed scanning lab's, which is deliberate: a lab must not
# depend on files outside its own directory, and a shared base image would make
# a change to one lab's tooling a change to the other's.
FROM miniinterneteth/d_host:latest

# The base image carries the nmap binary but NOT its script library:
# /usr/share/nmap/scripts is empty there, so --script banner, ftp-anon,
# http-title, http-enum and dns-zone-transfer all fail with "did not match a
# category, filename, or directory". nmap-scripts is what makes every NSE step in
# this range work, and the range's intel items are scored on findings four of
# those scripts produce.
#
# zmap and masscan are the two mass scanners the range compares against nmap.
# hydra drives the dictionary attack against the operations account. ncat, curl
# and the telnet client are how a learner confirms by hand what a scanner
# reported. iproute2 gives a full `ip` (the base image only has BusyBox's
# applet).
#
# sudo is the last door on the chain. The machine holding the flag carries a
# NOPASSWD rule letting a service account read one file as root, which `sudo -l`
# names in one command. It is a misconfiguration a defender fixes by deleting a
# line, which is the only kind of last step this range wants: nothing on the
# chain is an exploit, and nothing on it needs one.
#
# Seventeen service profiles can be drawn, and every daemon behind them is
# installed in every container, because one image serves every role and which
# daemon actually runs is decided by the profile script spawn.sh copies in.
# Three of the classes carry two implementations, drawn per host, so that
# identifying the software is a real task rather than a lookup a learner
# memorises after two spawns: lighttpd or darkhttpd behind `http`, OpenSSH or
# Dropbear behind `ssh`, chrony or OpenNTPD behind `ntp`.
#
# Six of the seventeen are UDP (SNMP, TFTP, NTP, syslog and DNS, which is both),
# which is the half of a survey a TCP-only range never teaches. The clients that
# talk to them are here too, because the attacker runs this same image: snmpwalk
# and snmpget from net-snmp-tools, the tftp client from tftp-hpa, redis-cli from
# redis, mosquitto_sub from mosquitto-clients, and rsync, which is its own
# client.
#
# socat is not a service anybody deploys; it is how three profiles that stand in
# for equipment with no packaged daemon are built. A print server speaking PJL on
# 9100 and a monitoring agent with a one-line protocol of its own are both real
# things to find on a network and neither has an Alpine package, so both are a
# socat listener in front of a shell script that answers the way the real thing
# does.
#
# bind is pinned to the 9.18 series for the same reason authoritative-dns pins
# it: the field manual names a version behind `version.bind`, and an unpinned
# `apk add bind` makes that true only for as long as the base image's Alpine
# branch happens to carry it. A branch move fails the build here, which is where
# a version change should surface.
RUN apk add --no-cache \
        nmap-scripts nmap-ncat \
        iptables \
        zmap masscan hydra \
        iproute2 curl inetutils-telnet \
        lighttpd darkhttpd vsftpd busybox-extras openssh dropbear \
        net-snmp net-snmp-tools tftp-hpa opensmtpd \
        redis rsync tinyproxy mosquitto mosquitto-clients \
        chrony openntpd socat iperf3 \
        sudo \
        'bind=~9.18' 'bind-tools=~9.18' \
    && mkdir -p /usr/share/minilabs /etc/minilabs/profile.d \
# masscan dlopen()s the unversioned "libpcap.so", which Alpine ships only in
# libpcap-dev; the runtime package provides libpcap.so.1 alone. Without this
# symlink every masscan run dies with "failed to load libpcap shared library",
# and a symlink is a great deal smaller than pulling in the -dev package.
    && ln -sf /usr/lib/libpcap.so.1 /usr/lib/libpcap.so

# The password list hydra works through. Fifty of the most common passwords in
# public breach corpora, which is what makes the attack a realistic one: no
# exploit is involved, only an account whose password appears on a list anybody
# can download. The operations account's password is drawn from the back half of
# this file, so a learner watches hydra work rather than hit it first try.
COPY passwords.txt /usr/share/minilabs/passwords.txt
RUN chmod 644 /usr/share/minilabs/passwords.txt

# The telnet service's login front-end, used instead of /bin/login. Its header
# explains why: busybox login re-prompts three times on one connection, which
# desyncs hydra's telnet module permanently after the first wrong password, so a
# dictionary attack would report "0 valid password found" with the password
# sitting in the list. It authenticates against the real /etc/shadow entry.
COPY lab-login /usr/local/bin/lab-login

# How the learner records findings. It appends to /root/findings.txt, validates
# only the SHAPE of a line, and never says whether a finding is right: no
# feedback in its output, none in its exit code, and no completion of addresses.
COPY report /usr/local/bin/report

RUN chmod 755 /usr/local/bin/lab-login /usr/local/bin/report
