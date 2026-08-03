# The RIR for the BGP prefix-hijacking lab: Krill, NLnet Labs' RPKI certificate
# authority, run in testbed mode.
#
# Testbed mode is what makes a self-contained RPKI possible. Krill normally sits
# under a real RIR's trust anchor; in testbed mode it embeds its own trust anchor
# and will issue a resource certificate to any child that asks, so this one
# container is the whole PKI: trust anchor, parent CA, publication server, and the
# web portal an operator logs into. Nothing in this lab talks to the real internet
# RPKI, and no real TAL is loaded.
#
# Built FROM the upstream published image rather than from source. The
# mini-internet builds Krill with cargo inside a multi-stage Alpine image; that
# costs a Rust toolchain and several minutes per build for a binary NLnet Labs
# already publish. The upstream image is Alpine with openssl, bash and wget, which
# is everything the start script below needs.
FROM nlnetlabs/krill:latest

# Krill's own generated TLS certificate carries no subjectAltName and a key hash
# for a CN, which Routinator rejects; a self-signed end-entity certificate used as
# its own root fails too, and fails silently ("No valid trust anchor", no further
# detail at any log level). start-krill therefore generates a real two-level chain,
# so openssl must be present -- it already is in this base, but the build fails
# loudly here if that ever changes.
RUN command -v openssl >/dev/null || { echo "openssl missing from base image" >&2; exit 1; }

COPY start-krill /usr/local/bin/start-krill
RUN chmod 755 /usr/local/bin/start-krill

EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/start-krill"]
