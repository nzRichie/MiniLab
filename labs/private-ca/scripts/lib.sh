#!/usr/bin/env bash
# Shared definitions for the private-CA web service lab lifecycle scripts.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnet, container
# names, IPs, interface names, file paths, the DNS name the certificate has to
# carry, and the four verify codes the lab is read by. Every other script sources
# it; never hardcode any of these in a second place.
#
# The lab is a configuration exercise, not an attack. Three hosts sit on one
# switched segment: a machine that runs a two-tier certificate authority, a web
# server that has to end up serving a certificate that authority issued, and a
# client that has to end up accepting it without being told to skip the check.

AS=111
DC=LAB
SW=S1

# ---------------------------------------------------------------------------
# One flat /24 behind one OVS bridge. Nothing in this lab is about routing, so
# there is no router and no second subnet: every host is one hop from every
# other, and the only thing standing between the client and the server's content
# is certificate verification.
SUBNET="111.0.0.0/24"
PREFIXLEN=24

CA_IP="111.0.0.10"        # runs the certificate authority; issues, never serves
SERVER_IP="111.0.0.20"    # runs the web service the certificate is issued for
CLIENT_IP="111.0.0.30"    # fetches the site, and decides whether to believe it

# ---------------------------------------------------------------------------
# Interface names. Every host has one NIC, named for the switch it plugs into,
# following the platform's <AS>-<SW> convention; the switch names each port after
# the host on the other end of it.
HOST_IF="${AS}-${SW}"

# ---------------------------------------------------------------------------
# The name the client asks for, and the name it must not accept.
#
# SERVER_NAME is what the client types into curl and what the certificate has to
# carry in its subjectAltName extension. It resolves through an /etc/hosts entry
# the client is delivered with, not through DNS: name resolution is not what this
# lab teaches, and a DNS server would be a fourth container answering a question
# nobody asks here.
#
# WRONG_NAME is the name the learner deliberately issues a certificate for in
# Part 4, to see what a client does when the name in the certificate and the name
# it asked for are both valid and different. It resolves nowhere, on purpose: the
# mismatch has to be between what was asked for and what was presented, not
# between two addresses.
SERVER_NAME="www.minilabs.lab"
WRONG_NAME="store.minilabs.lab"

# The name the server and the client reach the CA by, over SSH, to hand it a
# certificate signing request and collect what comes back.
CA_HOST="ca"

# ---------------------------------------------------------------------------
# The port the web service listens on, and the marker it serves.
#
# The marker is a distinctive string that appears nowhere else in the lab, so a
# fetch that returns it is unambiguous evidence that the web service answered
# rather than something else on the address. It is what separates the two
# failures a learner will otherwise conflate: a service that did not answer, and
# a service that answered with a certificate the client refused.
HTTPS_PORT=443
SITE_MARKER="PRIVATE-CA-SITE-7F2C91"
WEB_ROOT="/var/www/localhost/htdocs"

# ---------------------------------------------------------------------------
# The certificate authority's directory layout, on the CA container.
#
# Two tiers, each with its own key, its own issued-certificate database and its
# own serial counter, because that is what makes the missing-intermediate failure
# in Part 4 a real one: the client is given the root and only the root, so a
# server that does not send the intermediate leaves the client holding a
# certificate whose issuer it has never seen.
CA_DIR="/root/ca"
CA_CONF="${CA_DIR}/openssl.cnf"

ROOT_KEY="${CA_DIR}/root/private/root.key"
ROOT_CRT="${CA_DIR}/root/certs/root.crt"
INT_KEY="${CA_DIR}/int/private/int.key"
INT_CSR="${CA_DIR}/int/csr/int.csr"
INT_CRT="${CA_DIR}/int/certs/int.crt"

# Where a certificate signing request arrives from the server, and where the
# certificate issued against it is written.
CA_INBOX="${CA_DIR}/int/csr"
CA_ISSUED="${CA_DIR}/int/certs"

# The subject names the two authority certificates carry. Fixed so the handout
# can name them and status.sh can find them.
ROOT_SUBJ="/CN=MiniLabs Root CA"
INT_SUBJ="/CN=MiniLabs Issuing CA"

# ---------------------------------------------------------------------------
# The server's own TLS material.
#
# The private key never leaves this directory and never reaches the CA: what
# crosses to the CA is the signing request, which carries the public half and the
# name being asked for and nothing secret at all. That is the one property of the
# whole exercise a learner has to come away with, so the paths are named for it.
SRV_TLS_DIR="/etc/lighttpd/tls"
SRV_KEY="${SRV_TLS_DIR}/server.key"
SRV_CSR="${SRV_TLS_DIR}/server.csr"
SRV_CRT="${SRV_TLS_DIR}/server.crt"
SRV_INT="${SRV_TLS_DIR}/int.crt"
SRV_CHAIN="${SRV_TLS_DIR}/chain.pem"

# The certificate the server is delivered with: one it signed for itself, with no
# authority behind it. Part 1 is the learner finding out what a client makes of
# it. It lives beside the rest so the handout can point at both in one listing.
SELF_CRT="${SRV_TLS_DIR}/selfsigned.crt"
SELF_KEY="${SRV_TLS_DIR}/selfsigned.key"

# The three broken deployments Part 4 builds. Each is a whole PEM file the
# learner points lighttpd at, so switching between them is one edited line and
# one restart rather than a rebuild.
EXPIRED_CRT="${SRV_TLS_DIR}/expired.crt"
EXPIRED_CHAIN="${SRV_TLS_DIR}/expired-chain.pem"
WRONGNAME_CRT="${SRV_TLS_DIR}/wrongname.crt"
WRONGNAME_CHAIN="${SRV_TLS_DIR}/wrongname-chain.pem"

# The validity window the learner gives the expired certificate. Both ends are in
# the past, written in the ASN.1 GeneralizedTime form `openssl ca` wants, so the
# certificate is expired the moment it is issued and stays expired however long
# after the lab was written it is run.
EXPIRED_START="20240101000000Z"
EXPIRED_END="20240102000000Z"

# How long the certificates that are meant to work are valid for.
ROOT_DAYS=3650
INT_DAYS=1825
LEAF_DAYS=825

# ---------------------------------------------------------------------------
# lighttpd's configuration and its pid file. One instance, one socket, one
# certificate at a time: which certificate is what the learner changes.
LIGHTTPD_CONF="/etc/lighttpd/lighttpd.conf"
LIGHTTPD_PID="/run/lighttpd.pid"

# ---------------------------------------------------------------------------
# The client's trust store.
#
# TRUST_SRC is the directory update-ca-certificates reads a local anchor from;
# TRUST_BUNDLE is the single concatenated file curl and `openssl s_client
# -CAfile` are pointed at afterwards. Both are named because Part 3's step is to
# put a file in the first one and run the command that folds it into the second,
# and a learner who copies to the second one directly gets a trust store that
# works until the next update-ca-certificates run silently discards it.
TRUST_SRC="/usr/local/share/ca-certificates"
TRUST_ANCHOR="${TRUST_SRC}/minilabs-root.crt"
TRUST_BUNDLE="/etc/ssl/certs/ca-certificates.crt"

# ---------------------------------------------------------------------------
# The six verify codes this lab is read by. OpenSSL prints each as
# `Verify return code: <n> (<text>)` on the last line of an s_client session, and
# the number is the whole point of Part 4: curl reports every one of them as exit
# status 60, so the number is the only thing that says which of four different
# things went wrong.
#
# These are the values the handout quotes, and selftest.sh asserts each of them
# against a live run, so a change in OpenSSL's numbering surfaces here rather
# than in a student's marked answer.
VERIFY_OK=0              # X509_V_OK
VERIFY_SELFSIGNED=18     # X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT
VERIFY_EXPIRED=10        # X509_V_ERR_CERT_HAS_EXPIRED
VERIFY_UNTRUSTED_ROOT=20 # X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY
VERIFY_NO_ISSUER=21      # X509_V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE
VERIFY_HOSTNAME=62       # X509_V_ERR_HOSTNAME_MISMATCH

# 20 and 21 are the pair worth keeping straight, because curl prints the same
# words for both ("unable to get local issuer certificate") and they mean
# different things. 20 is what the client reports when the server sent a complete
# chain and the root at the top of it is not in the trust store: everything
# needed to build the chain arrived, and the anchor is missing. 21 is what it
# reports when the server sent the leaf alone: the certificate that would have
# continued the chain never arrived at all, so OpenSSL cannot even check the
# signature on the one it holds. This lab produces both, at different steps, from
# the same server.

# curl reports every certificate verification failure as this one exit status,
# whichever of the four it was. That collapse is what Part 4 is about.
CURL_TLS_FAIL=60

# ---------------------------------------------------------------------------
# Container names follow the platform convention, with L7 marking the lab's
# layer: <AS>_L7_<DC>_<name>. The switch carries the same prefix as the hosts
# even though it is a Layer 2 device, so status and teardown select the whole lab
# with a single filter.
SW_CTN="${AS}_L7_${DC}_${SW}"
CA_CTN="${AS}_L7_${DC}_ca"
SERVER_CTN="${AS}_L7_${DC}_server"
CLIENT_CTN="${AS}_L7_${DC}_client"

# Every host, in the order spawn wires and configures them.
HOSTS=(ca server client)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_ca"
SWITCH_IMAGE="miniinterneteth/d_switch"

# ovs-ctl rather than the image's supervisord entrypoint, and --no-mlockall
# rather than the default: under a rootless daemon CAP_IPC_LOCK cannot exceed
# RLIMIT_MEMLOCK, thread stacks fail to lock, and ovs-vswitchd dies on
# pthread_create before the bridge ever exists.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# otherwise only rebuilt when it is missing, which means an edit to
# image/Dockerfile never reaches a machine that built the image once: the
# container keeps running the previous version and the handout describes tooling
# the learner does not have.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

# Image preflight, called by spawn.sh before the first `docker run`.
ensure_images() {
    if ! docker image inspect "$SWITCH_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] pulling $SWITCH_IMAGE (first run only)"
        docker pull "$SWITCH_IMAGE" >/dev/null \
            || { echo "failed to pull $SWITCH_IMAGE" >&2; return 1; }
    fi
    if ! docker image inspect "$HOST_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] building $HOST_IMAGE from $LAB_DIR/image (first run only)"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to build $HOST_IMAGE" >&2; return 1; }
    elif image_older_than_source "$HOST_IMAGE" "$LAB_DIR/image"; then
        echo "[spawn] rebuilding $HOST_IMAGE: $LAB_DIR/image changed since it was built"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to rebuild $HOST_IMAGE" >&2; return 1; }
    fi
}

# ---------------------------------------------------------------------------
# Privileged host networking, performed from a helper container.
#
# Wiring a lab needs privileges a learner's account will not have: CAP_NET_ADMIN
# to create a veth pair, and CAP_SYS_ADMIN to enter a container's network
# namespace and rename the interface inside it. Rather than require root on the
# host, a throwaway --privileged container holds them.
#
# The helper keeps a network namespace of its own (--network=none). Both ends of
# every veth pair are moved out into lab containers, so the namespace the pair is
# created in never matters. Asking for the host's namespace (--network=host) only
# breaks the helper under a rootless daemon, where that namespace belongs to a
# user namespace the helper holds no privilege in and every `ip link add` returns
# EPERM. --pid=host stays: it is what makes each lab container's
# /proc/<pid>/ns/net reachable for the moves.
#
# Renames run through `nsenter --net`, not `ip netns exec`. iproute2 remounts
# /sys on every namespace switch and a user namespace forbids that, while the
# rename itself is pure netlink and needs no sysfs at all.
HELPER_CTN="$( ctn_of netadmin_helper )"

helper_start() {
    docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true
    docker run -d --rm --name "$HELPER_CTN" \
        --privileged --network=none --pid=host \
        "$HOST_IMAGE" sleep 600 >/dev/null
    for _ in $(seq 1 40); do
        if docker exec "$HELPER_CTN" true >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    echo "helper container $HELPER_CTN did not become ready" >&2
    return 1
}

# Run one privileged networking command inside the helper.
helper() { docker exec "$HELPER_CTN" "$@"; }

helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }

# ---------------------------------------------------------------------------
# Shared read-only probes. status.sh and selftest.sh both need these, and a
# second copy of any of them is a chance for the two to disagree about what the
# lab's success condition is.

# The verify code the client's OpenSSL reports for a TLS session to <name>,
# checking the presented certificate against the client's own trust store and
# against the name that was asked for.
#
# -verify_hostname is not optional. `openssl s_client` builds and checks the
# chain by default, but it checks NO name unless it is given one, so without this
# flag a certificate issued for a completely different host still comes back
# `Verify return code: 0 (ok)` and Part 4's name-mismatch failure does not exist.
# -servername sends the name in the TLS Server Name Indication extension, which
# is what a browser does and what makes the request the same one curl makes.
#
# Prints the bare number, or the empty string when the session produced no verify
# line at all (nothing listening, or the handshake failed before a certificate
# was presented).
verify_code() {   # <name>
    docker exec "$CLIENT_CTN" sh -c \
        "echo | openssl s_client -connect '${1}:${HTTPS_PORT}' -servername '${1}' \
             -verify_hostname '${1}' -CAfile '${TRUST_BUNDLE}' 2>/dev/null \
         | sed -n 's/^ *Verify return code: \\([0-9]*\\).*/\\1/p' | tail -1"
}

# The whole `Verify return code:` line, number and text, for status.sh to print
# and for the handout's quoted output to be checked against.
verify_line() {   # <name>
    docker exec "$CLIENT_CTN" sh -c \
        "echo | openssl s_client -connect '${1}:${HTTPS_PORT}' -servername '${1}' \
             -verify_hostname '${1}' -CAfile '${TRUST_BUNDLE}' 2>/dev/null \
         | sed -n 's/^ *\\(Verify return code:.*\\)/\\1/p' | tail -1"
}

# How many certificates the server sends in its Certificate message. This is the
# one fact that separates a correctly deployed chain from Part 4's third failure,
# and it is read from the wire rather than from the server's own files, because
# what the server holds on disk and what it puts on the wire are exactly the two
# things that failure has disagreeing.
chain_length() {   # <name>
    docker exec "$CLIENT_CTN" sh -c \
        "echo | openssl s_client -connect '${1}:${HTTPS_PORT}' -servername '${1}' \
             -showcerts 2>/dev/null | grep -c 'BEGIN CERTIFICATE'"
}

# The subject line of each certificate the server sends, innermost first.
chain_subjects() {   # <name>
    docker exec "$CLIENT_CTN" sh -c \
        "echo | openssl s_client -connect '${1}:${HTTPS_PORT}' -servername '${1}' \
             2>/dev/null | sed -n 's/^ *[0-9] s:\\(.*\\)/\\1/p'"
}

# Fetch the site from the client with verification ON, and print the body. Empty
# when curl refused the certificate, which is the whole point: this is the call
# the lab has to end up satisfying.
curl_verified() {   # <name>
    docker exec "$CLIENT_CTN" curl -s --max-time 8 "https://${1}/" 2>/dev/null
}

# curl's exit status for that same fetch. 0 when the certificate verified, 60 for
# every verification failure whatever its cause.
curl_status() {   # <name>
    docker exec "$CLIENT_CTN" sh -c \
        "curl -s -o /dev/null --max-time 8 'https://${1}/' >/dev/null 2>&1; echo \$?"
}

# curl's own message for a failed fetch, which names the cause in words where the
# exit status does not.
curl_message() {   # <name>
    docker exec "$CLIENT_CTN" sh -c \
        "curl -sS -o /dev/null --max-time 8 'https://${1}/' 2>&1 | head -1"
}

# The same fetch with verification switched off. Used only to establish that the
# web service is serving the marker and that the certificate is the only thing in
# the way; a lab that ends here has not been done.
curl_insecure() {   # <name>
    docker exec "$CLIENT_CTN" curl -sk --max-time 8 "https://${1}/" 2>/dev/null
}

# True when the client's trust bundle holds the certificate at <path on the CA>.
#
# Matched on one line of the certificate's own base64 body rather than by
# subject, because two certificates can carry the same subject and only one of
# them is the one the CA actually signed with, and rather than through
# `openssl verify`, because an intermediate verifies against a bundle holding
# only the root: that answers "does this chain" and the question here is "is this
# file in that file".
#
# The grep runs inside the container and its result is captured before it is
# tested. A `docker exec ... | grep -q` pipeline looks equivalent and is not:
# grep -q exits at the first match, docker exec takes SIGPIPE, and under
# `set -o pipefail` the caller reads that as a failure on every successful match.
trusts_ca_cert() {   # <path on the CA container>
    local body hit
    body="$( docker exec "$CA_CTN" sed -n '2p' "$1" 2>/dev/null | tr -d '\r' )"
    [ -n "$body" ] || return 1
    hit="$( docker exec "$CLIENT_CTN" grep -c -F -- "$body" "$TRUST_BUNDLE" 2>/dev/null | tr -d '\r' )"
    case "$hit" in ''|0|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# The subjectAltName extension of a certificate on the server, as one line.
cert_san() {   # <path on the server container>
    docker exec "$SERVER_CTN" sh -c \
        "openssl x509 -in '$1' -noout -ext subjectAltName 2>/dev/null | tail -n +2 | tr -d ' \\r'"
}

# The subject and issuer of a certificate on the server, one per line.
cert_subject() { docker exec "$SERVER_CTN" sh -c "openssl x509 -in '$1' -noout -subject 2>/dev/null | sed 's/^subject=//'"; }
cert_issuer()  { docker exec "$SERVER_CTN" sh -c "openssl x509 -in '$1' -noout -issuer  2>/dev/null | sed 's/^issuer=//'"; }

# True when a certificate on the CA carries a CA:TRUE basic constraint, which is
# what makes it able to sign other certificates rather than only identify a
# service.
is_ca_cert() {   # <path on the CA container>
    local out
    out="$( docker exec "$CA_CTN" sh -c \
              "openssl x509 -in '$1' -noout -text 2>/dev/null" 2>/dev/null )"
    case "$out" in *CA:TRUE*) return 0 ;; *) return 1 ;; esac
}

# True when the intermediate certificate verifies as issued by the root. This is
# `openssl verify` doing on two files what the client does on the wire, and it is
# how status.sh checks Part 2 before any web service exists to check it through.
int_chains_to_root() {
    docker exec "$CA_CTN" sh -c \
        "openssl verify -CAfile '$ROOT_CRT' '$INT_CRT' >/dev/null 2>&1"
}

# True when lighttpd is listening on the TLS port.
server_is_listening() {
    docker exec "$SERVER_CTN" netstat -tln 2>/dev/null \
        | awk -v p=":${HTTPS_PORT}" '$1 == "tcp" && $4 ~ p"$" { found = 1 } END { exit !found }'
}

# The certificate lighttpd is configured to present, read out of its own config
# rather than guessed, because Part 4 changes exactly this line three times.
configured_pemfile() {
    docker exec "$SERVER_CTN" sh -c \
        "sed -n 's/^[[:space:]]*ssl.pemfile[[:space:]]*=[[:space:]]*\"\\(.*\\)\"/\\1/p' '$LIGHTTPD_CONF' 2>/dev/null | tail -1"
}
