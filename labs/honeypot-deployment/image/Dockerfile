# Host image for the honeypot deployment lab.
# One image serves every role on top of the stock mini-internet host image (which
# already ships tcpdump, nmap/nping, ping, dig, wget and an sshd):
#   * attacker  logs into the production host, then into whatever answers on its
#               port 22 after the learner has been at the router
#   * router    forwards between four subnets; the only device the learner writes
#               packet-filter config on
#   * prod      the protected host: a real sshd and a real web service
#   * admin     the management station whose access has to survive the defence
#   * honeypot  Cowrie, installed but deliberately NOT configured
FROM miniinterneteth/d_host:latest

# iproute2 gives a full `ip` (the base image only has BusyBox's applet). nftables
# is where both defence stages are written. openssh-client is absent from the base
# image, which ships the server only, so neither the attacker nor the admin could
# open a session without it. sshpass drives the non-interactive logins in
# selftest.sh; the handout never uses it, because a learner types the password.
# lighttpd and curl are the production web service and the way its content is read.
RUN apk add --no-cache \
        iproute2 nftables \
        openssh-client sshpass \
        lighttpd curl \
        python3 py3-pip

# Cowrie, the low-interaction SSH honeypot the learner deploys in Part 2.
#
# It goes in a virtualenv rather than into the system site-packages because
# Alpine's Python is marked externally-managed (PEP 668) and a bare `pip install`
# refuses to touch it. The venv also pins Cowrie's dependency tree away from the
# system one, so an apk upgrade cannot half-break the honeypot.
#
# 3.0.12 is a pure-Python wheel and its compiled dependencies (cryptography,
# bcrypt) all publish musl wheels, so this resolves without a compiler in the
# image and without a Rust toolchain.
RUN python3 -m venv /opt/cowrie-venv \
    && /opt/cowrie-venv/bin/pip install --no-cache-dir cowrie==3.0.12 \
    && /opt/cowrie-venv/bin/pip cache purge >/dev/null 2>&1 || true

# Cowrie refuses to run as root and exits before it parses its arguments, so the
# honeypot needs an unprivileged account to run under. That is also why the
# honeypot listens on 2222 rather than 22: an unprivileged process cannot bind a
# port below 1024, which is why the redirect the learner writes in Part 2 has a
# port in it as well as an address.
#
# That last part is only true because scripts/spawn.sh sets
# net.ipv4.ip_unprivileged_port_start back to 1024 on every container. The
# boundary is a per-network-namespace sysctl and Docker sets it to 0, so in a
# default container this account binds 22 quite happily. Do not drop the sysctl
# thinking it is decoration: question 4 is graded on the reasoning above.
RUN adduser -D -h /opt/cowrie -s /bin/sh cowrie

# The state directory Cowrie runs out of. `cowrie start` refuses to launch unless
# the working directory holds etc/cowrie.cfg or etc/cowrie.cfg.dist, and it writes
# its logs and its captured artifacts under var/, so the tree has to exist before
# the honeypot can be configured at all.
#
# The defaults template and the example user database are copied out of the
# installed package; the real etc/cowrie.cfg is deliberately NOT created here.
# Writing it is the learner's Part 2 work, and an image that shipped a working
# config would hand over the graded half of the lab.
#
# Modes are set explicitly rather than left to the ambient umask: `docker exec`
# runs with umask 0022 under a rootful daemon and 0000 under a rootless one, so a
# bare mkdir would give 755 on one host and 777 on the other.
RUN COWRIE_DATA="$( /opt/cowrie-venv/bin/python -c 'import cowrie, os; print(os.path.join(os.path.dirname(cowrie.__file__), "data"))' )" \
    && mkdir -p /opt/cowrie/etc /opt/cowrie/var/log/cowrie /opt/cowrie/var/run \
                /opt/cowrie/var/lib/cowrie/downloads /opt/cowrie/var/lib/cowrie/tty \
    && cp "$COWRIE_DATA/etc/cowrie.cfg.dist" /opt/cowrie/etc/cowrie.cfg.dist \
    && cp "$COWRIE_DATA/etc/userdb.example" /opt/cowrie/etc/userdb.example \
    && chown -R cowrie:cowrie /opt/cowrie \
    && chmod 755 /opt/cowrie /opt/cowrie/etc /opt/cowrie/var /opt/cowrie/var/log \
                 /opt/cowrie/var/log/cowrie /opt/cowrie/var/run \
                 /opt/cowrie/var/lib /opt/cowrie/var/lib/cowrie \
                 /opt/cowrie/var/lib/cowrie/downloads /opt/cowrie/var/lib/cowrie/tty \
    && chmod 644 /opt/cowrie/etc/cowrie.cfg.dist /opt/cowrie/etc/userdb.example
