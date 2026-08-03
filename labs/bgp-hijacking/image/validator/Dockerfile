# The Relying Party cache for the BGP prefix-hijacking lab: Routinator, NLnet Labs'
# RPKI validator.
#
# A ROA sitting in the RIR's repository changes nothing on its own. A relying party
# has to fetch the repository, check every signature back to the trust anchor, and
# turn what survives into Validated ROA Payloads: plain (prefix, max length, origin
# AS) triples. It then feeds those to routers over RTR, and only then can a router
# call a route Valid or Invalid. This container is that step.
#
# Built FROM the upstream published image for the same reason as the RIR: NLnet
# Labs publish the binary, and building it from source would pull a Rust toolchain
# into a lab that boots on a laptop.
FROM nlnetlabs/routinator:latest

COPY start-routinator /usr/local/bin/start-routinator

# The base image runs as an unprivileged user and the start script writes its
# config, TAL and cache under that user's home, so both must be owned by it.
USER 0
RUN chmod 755 /usr/local/bin/start-routinator \
    && mkdir -p /home/routinator/tals /home/routinator/.rpki-cache \
    && chown -R routinator:routinator /home/routinator
USER routinator

EXPOSE 3323 9556
ENTRYPOINT ["/usr/local/bin/start-routinator"]
