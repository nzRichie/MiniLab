# Host image for the botnet lab. One image serves every role on top of the
# stock mini-internet host image (which already ships tcpdump, nmap, netstat,
# wget, an OpenSSH server and a busybox `ip`):
#
#   router                 forwards between the three legs; the only place a
#                          policy can see recruitment, tasking or payload
#                          delivery, and the machine the learner writes iptables
#                          rules on
#   server                 the inside network: lighttpd on tcp/80 and sshd on
#                          tcp/22, with an account whose password is on the
#                          wordlist. What the population is eventually tasked
#                          against
#   admin                  the site's own workstation. Fetches the page and logs
#                          into the server on a timer; runs no service itself,
#                          so the botnet never recruits it
#   host1 .. host6         the field. Ordinary machines running sshd, four of
#                          them sharing one weak root password
#   c2                     the learner's controller runs here (c2.py); nothing
#                          starts at spawn
#   loader                 lighttpd serving bot.py and the wordlist, access log on
FROM miniinterneteth/d_host:latest

# python3       the bot and the controller.
# openssh-client + sshpass  recruitment from the c2, the admin's SSH probe, and
#               the distributed guessing task, all of which drive ssh
#               non-interactively. The base image ships the server only.
# lighttpd      the loader and the inside server's web service. Used unmodified:
#               the stock config already serves /var/www/localhost/htdocs with
#               index.html as an index file.
# iptables      the learner's whole answer in Part 4. The base image ships none.
# iproute2      a full `ip`; the base image's /sbin/ip is busybox, whose applet
#               has no `ip -o` output format, which the lifecycle scripts parse.
# tcpdump is already in the base image; the captures Part 4 opens with use it.
# curl drives the admin's web probe, which reads an HTTP status code with
# curl's -w '%{http_code}'; the base image ships wget but not curl.
RUN apk add --no-cache \
        python3 \
        openssh-client \
        sshpass \
        lighttpd \
        iptables \
        iproute2 \
        curl

# A client config for the lab's own addresses, so an ssh in this lab is one
# readable command rather than one command carrying five -o flags. The stock
# /etc/ssh/ssh_config is a single `Include /etc/ssh/ssh_config.d/*.conf` and
# nothing else, so a drop-in file is the whole of the change. Every setting is
# here because the lab needs it:
#
#   StrictHostKeyChecking no, UserKnownHostsFile /dev/null
#       each field host regenerates its host key on every spawn, so a remembered
#       key would refuse the next login
#   LogLevel ERROR
#       drops the "Permanently added ... to the list of known hosts" line the two
#       settings above print on every connection. It does NOT hide an
#       authentication failure: "Permission denied" is still printed, which is
#       what the learner needs to see when a password does not work
#   PreferredAuthentications password, PubkeyAuthentication no
#       no account in this lab has an authorized key, so offering one first costs
#       a round trip and nothing else
#   ConnectTimeout 4
#       Part 2's standing task opens an SSH connection to 98 addresses of which
#       94 hold no machine; without a bound each of those waits out the kernel's
#       full TCP retry
#
# Scoped to Host 128.*, which is the lab's own /8 and the only place any of this
# is true. The handout's "The setup" section states that this file exists and
# what is in it, because a learner who never sees these options still has to know
# ssh is not checking host keys here.
RUN mkdir -p /etc/ssh/ssh_config.d \
 && printf '%s\n' \
        'Host 128.*' \
        '    StrictHostKeyChecking no' \
        '    UserKnownHostsFile /dev/null' \
        '    LogLevel ERROR' \
        '    PreferredAuthentications password' \
        '    PubkeyAuthentication no' \
        '    ConnectTimeout 4' \
        > /etc/ssh/ssh_config.d/10-minilabs.conf \
 && chmod 755 /etc/ssh/ssh_config.d \
 && chmod 644 /etc/ssh/ssh_config.d/10-minilabs.conf

# The payload and the controller. bot.py is copied into the image AND served by
# the loader at spawn from a copy under the document root, so the byte the
# learner fetches is the byte in the image; selftest.sh checks the two match.
# c2.py is installed as `c2` on PATH so the operator types `c2` and the
# lifecycle scripts run `c2 -c`.
COPY bot.py /usr/local/lib/minilabs/bot.py
COPY c2.py  /usr/local/bin/c2
COPY probe-web.sh /usr/local/lib/minilabs/probe-web.sh
COPY probe-ssh.sh /usr/local/lib/minilabs/probe-ssh.sh
RUN chmod 755 /usr/local/lib/minilabs/bot.py \
              /usr/local/bin/c2 \
              /usr/local/lib/minilabs/probe-web.sh \
              /usr/local/lib/minilabs/probe-ssh.sh

# The marker the payload refuses to run without (guard 1 in bot.py). It is
# written here and nowhere else, so a copy of bot.py that escapes onto a machine
# that is not a lab container finds no marker and exits. Baking it into the
# image is what makes the guard hold without the learner having to trust the
# handout.
RUN echo "MiniLabs botnet lab. This host is an isolated lab container." \
        > /etc/minilabs-lab

# The directories the lab writes into, created here so their modes do not depend
# on the daemon's umask, which differs between a rootful and a rootless Docker.
RUN mkdir -p /run/minilabs /var/lib/c2 /var/lib/minilabs /var/log/lighttpd \
 && chmod 755 /run/minilabs /var/lib/c2 /var/lib/minilabs /var/log/lighttpd
