# Images for the YARA rule authoring and generalisation lab.
#
# This is the second family of labs off debian rather than miniinterneteth/d_host,
# after stack-overflow, and the reason is packaging rather than libc. Trixie main
# carries yara 4.5.2, pev 0.84, upx-ucl 4.2.4, clamav 1.4.3, python3-pefile
# 2024.8.26 and gcc-mingw-w64-x86-64 14.2.0 in one release. Alpine packages none
# of the four that matter, and bookworm dropped upx-ucl, so the packed half of
# the corpus has no sample on the older base.
#
# Three stages, and the split between the last two is what keeps the holdout
# out of the learner's reach:
#
#   samples    compiles every PE from src/ with the mingw cross-compiler and
#              packs the ones that are meant to be packed. The compiler and the
#              packer stay in this stage; neither reaches a shipped image.
#   analysis   the workstation, the scanner and the client all run this. It
#              carries /srv/corpus and the two files the client uploads, and
#              carries no holdout sample at all.
#   holdout    one container runs this. It carries /srv/holdout and yara, and
#              nothing else in the lab has a copy of those ten files.
#
# Build both shipped stages:
#   docker build --target analysis -t d_host_yara      image/
#   docker build --target holdout  -t d_host_yara_hold image/

# ---------------------------------------------------------------------------
FROM debian:trixie-slim AS samples

# gcc-mingw-w64-x86-64 cross-compiles a genuine PE32+ from C on Linux, so every
# artefact in the corpus is a real Windows binary with a real import table and a
# real section layout, and every property the handout quotes is a property of
# that exact build. binutils-mingw-w64-x86-64 supplies windres, which compiles a
# configuration block into an RCDATA resource for the builds that carry it
# there. upx-ucl 4.2.4 is the packer.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc-mingw-w64-x86-64 \
        binutils-mingw-w64-x86-64 \
        upx-ucl \
    && rm -rf /var/lib/apt/lists/*

COPY src /src
COPY build-samples.sh /build-samples.sh
RUN chmod 755 /build-samples.sh && /build-samples.sh

# ---------------------------------------------------------------------------
FROM debian:trixie-slim AS analysis

# yara is the tool the lab is about, and the pev suite is how a learner reads
# the features a rule is written against: readpe prints the section table, the
# data directories and the import descriptors, pestr prints a string with the
# offset it sits at, peldd prints the DLL names, pehash prints the imphash and
# pescan prints the heuristic scanner's verdict. python3-pefile is the same
# structure access from a script. upx-ucl is here so a learner can decompress a
# packed sample and compare it against its own packed build; it never packs
# anything in a shipped image.
#
# clamav supplies clamscan, which is the scanner Part 4 deploys to; lighttpd
# with mod_cgi is the upload endpoint in front of it, and curl is how the
# client posts a file to that endpoint.
#
# iproute2 gives ip and util-linux gives nsenter, which are what the wiring
# helper container needs; procps supplies pgrep and pkill for the lifecycle
# scripts. file, xxd and less are how a learner looks at a sample without a
# hex editor.
RUN apt-get update && apt-get install -y --no-install-recommends \
        yara \
        pev \
        upx-ucl \
        clamav \
        python3 \
        python3-pefile \
        lighttpd \
        curl \
        iproute2 \
        util-linux \
        procps \
        iputils-ping \
        file \
        xxd \
        less \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# clamscan reads /var/lib/clamav when it is given no -d, and the package ships
# that directory empty because no signature database was ever downloaded. Every
# scan in this lab names its database with -d, so the directory is never
# consulted; the placeholder keeps clamscan from complaining about a missing
# directory if a learner runs it with no arguments.
RUN mkdir -p /var/lib/clamav /etc/minilabs /var/spool/uploads \
    && chmod 755 /var/lib/clamav /etc/minilabs /var/spool/uploads

# The corpus, read-only. set-a is what Part 1 scans; set-b is what Part 2 adds.
# Family builds are named nightjar-NN.exe and benign ones bn-NN.exe: this lab
# hands the labels over, because what it grades is the rule and not the triage.
COPY --from=samples /out/corpus /srv/corpus

# The two files the client posts to the scanner in Part 4. They sit in the
# image rather than on the workstation's corpus share because the client is the
# machine that uploads them.
COPY --from=samples /out/uploads /usr/local/share/minilabs/uploads

# The upload endpoint's CGI, installed from here on every spawn and every reset
# so a learner who edited it gets the original back.
COPY upload.cgi /usr/local/lib/minilabs/upload.cgi

RUN chmod 755 /usr/local/lib/minilabs/upload.cgi \
    && chmod -R a-w /srv/corpus \
    && mkdir -p /var/log/lighttpd \
    && chmod 755 /var/log/lighttpd

# ---------------------------------------------------------------------------
FROM debian:trixie-slim AS holdout

# The scoring appliance. It runs yara against the rule file status.sh copies in
# and prints two counts. It carries no compiler, no packer, no pev and no
# clamav, because it does nothing but scan.
RUN apt-get update && apt-get install -y --no-install-recommends \
        yara \
        iproute2 \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY --from=samples /out/holdout /srv/holdout
RUN chmod 755 /srv/holdout && chmod -R a-w /srv/holdout
