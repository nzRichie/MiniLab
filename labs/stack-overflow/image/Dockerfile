# Host image for the stack overflow and build-hardening lab.
#
# This is the only lab in the catalogue that does not build on
# miniinterneteth/d_host, and the reason is the C library. Every observation in
# Part 2 is something a libc either does or does not do:
#
#   * glibc's __stack_chk_fail prints `*** stack smashing detected ***:
#     terminated` before it aborts. musl's crashes with an illegal instruction
#     and prints nothing, so the stage that matters most would have no message
#     to read.
#   * glibc implements _FORTIFY_SOURCE, so `nm` on a build made with it shows
#     __memcpy_chk and __printf_chk and the learner can see the flag took
#     effect. Alpine ships no fortify support in musl-dev at all, so the flag
#     would be a no-op and the stage would teach a fact about musl rather than
#     a fact about the flag.
#
# The wiring helper container runs this image too. It needs `ip` (iproute2) and
# `nsenter` (util-linux); both are installed below, so the veth plumbing is the
# same as every other lab's.
#
# One image serves every role:
#   * svc       the appliance running devregd; Part 1 is debugged here and every
#               Part 2 rebuild is compiled here
#   * ops       the operator's workstation; the legitimate caller, and the
#               liveness check every hardening stage is measured against
#   * attacker  the machine that sends the overflow and reads the recovery key
FROM debian:bookworm-slim

# gcc and libc6-dev build the five variants in Part 2. gdb is how Part 1 finds
# the offset to the saved return address; binutils supplies nm, objdump and
# readelf, which are how the learner reads a symbol's address and checks that a
# hardening flag reached the binary. python3 writes the payload's raw bytes:
# an address is eight bytes, most of them outside the printable range, and
# nothing in a POSIX shell writes those as conveniently.
#
# netcat-openbsd is the client for every request in this lab; its -q flag is
# what makes a one-shot request wait for the reply and then close. iproute2 and
# util-linux are for the wiring helper and for setarch. procps supplies pgrep
# and pkill, which is how the service is restarted between stages.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        libc6-dev \
        gdb \
        binutils \
        python3 \
        netcat-openbsd \
        iproute2 \
        util-linux \
        procps \
        iputils-ping \
        xxd \
        file \
        less \
    && rm -rf /var/lib/apt/lists/*

# The source the learner reads and rebuilds, and the binary they attack.
#
# Mode 0444 root:root says the source is not the thing to change, but it does
# not enforce it: every shell in this lab is root inside its container, and root
# carries CAP_DAC_OVERRIDE, so the mode is a signal and not a lock. The
# enforcement is the pristine copy under /usr/local/share: default_config/svc.sh
# restores the source from it on every spawn and every reset, so a lab that has
# been reset is a lab whose program the handout still describes.
#
# Every mode here is set explicitly rather than left to the ambient umask.
# docker exec runs with umask 0022 under a rootful daemon and 0000 under a
# rootless one, so a bare mkdir yields 755 on one and 777 on the other.
RUN mkdir -p /opt/devreg/src /opt/devreg/bin /usr/local/share/minilabs
COPY devregd.c /opt/devreg/src/devregd.c
COPY devregd.c /usr/local/share/minilabs/devregd.c
RUN chmod 755 /opt/devreg /opt/devreg/src /opt/devreg/bin /usr/local/share/minilabs \
    && chmod 444 /opt/devreg/src/devregd.c /usr/local/share/minilabs/devregd.c

# The vulnerable build, compiled here so the binary the learner attacks and the
# source the handout quotes are the same build on every machine.
#
# -no-pie is an opt-OUT: this image's gcc (Debian 12.2.0) is configured with
# --enable-default-pie, so a bare `gcc -o devregd devregd.c` would already
# produce a position-independent binary. It is not configured with
# --enable-default-ssp, so no canary is added by default and
# -fno-stack-protector changes nothing here; it is written anyway so the
# baseline says what it is rather than depending on how the toolchain was
# configured. A vendor shipping an appliance built with neither is what this
# binary represents.
#
# -O0 keeps the generated code close to the source at /opt/devreg/src/devregd.c,
# so a learner reading the disassembly can follow it back to the loop.
RUN gcc -O0 -fno-stack-protector -no-pie \
        -o /opt/devreg/bin/devregd /opt/devreg/src/devregd.c \
    && chmod 755 /opt/devreg/bin/devregd

# Where the service writes its own output. The C library's abort message from a
# child killed by the stack canary lands here, because the child's standard
# error is the only one of its three descriptors the server does not replace
# with the socket.
RUN touch /var/log/devregd.log && chmod 644 /var/log/devregd.log
