#!/usr/bin/env bash
# Show what the lab is doing, and its success oracle.
#
# The oracle is the last stage: the verify code the client's OpenSSL reports for
# a session to www.minilabs.lab, and whether curl returns the site's marker with
# verification switched on. Code 0 and the marker together are the one fact a
# script can read without a human judging a configuration, and no arrangement of
# files produces them except the intended one.
#
# The four stages above it exist because a single red oracle says nothing about
# which of thirty commands was wrong: the authority, the certificate, what the
# server puts on the wire, and what the client is willing to believe each fail in
# a different place and each fail with the oracle looking identical.
#
# Nothing here configures anything. It reads state and prints it.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

pass=0; fail=0
mark() {   # <yes|no> <text>
    if [ "$1" = "yes" ]; then pass=$((pass+1)); printf '  [ ok ] %s\n' "$2"
    else                      fail=$((fail+1)); printf '  [    ] %s\n' "$2"; fi
}

ca_has()  { docker exec "$CA_CTN"     test -f "$1" 2>/dev/null; }
srv_has() { docker exec "$SERVER_CTN" test -f "$1" 2>/dev/null; }

echo "== containers =="
docker ps --filter "name=${AS}_L7_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -v netadmin_helper
echo

echo "== what this lab asks for =="
printf '  %-34s %s\n' "issued by:"        "an authority the client has been given, not the server"
printf '  %-34s %s\n' "carrying the name:" "$SERVER_NAME"
printf '  %-34s %s\n' "sent as:"          "the server's certificate and the intermediate's, in that order"
printf '  %-34s %s\n' "read by:"          "openssl s_client on ${CLIENT_CTN}, and curl with no -k"
echo

# ---------------------------------------------------------------------------
echo "== stage 1: the certificate authority =="
if ca_has "$ROOT_CRT"; then
    mark yes "the root certificate exists"
    if is_ca_cert "$ROOT_CRT"; then
        mark yes "the root carries basicConstraints CA:TRUE, so it may sign certificates"
    else
        mark no  "the root does not carry CA:TRUE; it cannot sign anything"
    fi
else
    mark no "no root certificate yet ($ROOT_CRT)"
fi

if ca_has "$INT_CRT"; then
    mark yes "the intermediate certificate exists"
    if is_ca_cert "$INT_CRT"; then
        mark yes "the intermediate carries CA:TRUE"
    else
        mark no  "the intermediate does not carry CA:TRUE"
    fi
    if int_chains_to_root; then
        mark yes "the intermediate verifies as issued by the root"
    else
        mark no  "the intermediate does not verify against the root"
    fi
else
    mark no "no intermediate certificate yet ($INT_CRT)"
fi

if ca_has "$ROOT_CRT" || ca_has "$INT_CRT"; then
    echo
    echo "  what the authority has issued (${CA_DIR}/int/index.txt):"
    docker exec "$CA_CTN" sh -c "cat '${CA_DIR}/int/index.txt'" 2>/dev/null \
        | awk '{ printf "    status=%s expires=%s serial=%s subject=%s\n", $1, $2, $3, $NF }'
    printf '    next serial: %s\n' \
        "$( docker exec "$CA_CTN" sh -c "cat '${CA_DIR}/int/serial'" 2>/dev/null )"
fi
echo

# ---------------------------------------------------------------------------
echo "== stage 2: the server's certificate, on disk =="
if srv_has "$SRV_CRT"; then
    mark yes "the server holds a certificate at $SRV_CRT"
    issuer="$( cert_issuer "$SRV_CRT" )"
    if [ "$issuer" = "CN = ${INT_SUBJ#/CN=}" ]; then
        mark yes "it was issued by ${INT_SUBJ#/CN=}"
    else
        mark no  "its issuer is '${issuer:-unreadable}', not ${INT_SUBJ#/CN=}"
    fi
    san="$( cert_san "$SRV_CRT" )"
    if [ "$san" = "DNS:${SERVER_NAME}" ]; then
        mark yes "its subjectAltName is DNS:${SERVER_NAME}"
    else
        mark no  "its subjectAltName is '${san:-absent}', not DNS:${SERVER_NAME}"
    fi
    if docker exec "$SERVER_CTN" openssl x509 -in "$SRV_CRT" -noout -checkend 0 >/dev/null 2>&1; then
        mark yes "it is inside its validity period"
    else
        mark no  "it is outside its validity period"
    fi
else
    mark no "the server holds no issued certificate yet ($SRV_CRT)"
fi

if srv_has "$SRV_KEY"; then
    mode="$( docker exec "$SERVER_CTN" stat -c '%a' "$SRV_KEY" 2>/dev/null )"
    if [ $(( 0${mode:-777} & 077 )) -eq 0 ]; then
        mark yes "the private key is mode ${mode}, readable by nobody but its owner"
    else
        mark no  "the private key is mode ${mode}, readable by group or other"
    fi
fi
echo

# ---------------------------------------------------------------------------
echo "== stage 3: what the server puts on the wire =="
if server_is_listening; then
    mark yes "lighttpd is listening on tcp/${HTTPS_PORT}"
    printf '  presenting: %s\n' "$( configured_pemfile )"
    n="$( chain_length "$SERVER_NAME" )"
    if [ "${n:-0}" -ge 2 ]; then
        mark yes "it sends ${n} certificates, so the chain reaches the root the client holds"
    else
        mark no  "it sends ${n:-0} certificate; the client is left holding an issuer it has never seen"
    fi
    echo "  subjects, innermost first:"
    chain_subjects "$SERVER_NAME" | sed 's/^/    /'
else
    mark no "nothing is listening on tcp/${HTTPS_PORT}"
fi
echo

# ---------------------------------------------------------------------------
echo "== stage 4: what the client is willing to believe =="
if ca_has "$ROOT_CRT" && trusts_ca_cert "$ROOT_CRT"; then
    mark yes "the root certificate is in the client's trust bundle"
else
    mark no  "the root certificate is not in the client's trust bundle"
fi
if ca_has "$INT_CRT" && trusts_ca_cert "$INT_CRT"; then
    mark no  "the INTERMEDIATE is also in the trust bundle; the server should be sending it, not the client trusting it"
else
    mark yes "the intermediate is not a trust anchor, which is right: the server sends it"
fi
echo

# ---------------------------------------------------------------------------
echo "== oracle: what the client makes of the certificate =="
line="$( verify_line "$SERVER_NAME" )"
code="$( verify_code "$SERVER_NAME" )"
cstat="$( curl_status "$SERVER_NAME" )"
body="$( curl_verified "$SERVER_NAME" )"

printf '  openssl s_client: %s\n' "${line:-no session, nothing answered on tcp/${HTTPS_PORT}}"
if [ -z "$code" ]; then
    :
elif [ "$code" = "$VERIFY_OK" ]; then
    mark yes "verify code ${VERIFY_OK}: the chain built to a trusted root and the name matched"
else
    case "$code" in
        "$VERIFY_SELFSIGNED") why="nothing vouches for this certificate but itself" ;;
        "$VERIFY_EXPIRED")    why="the certificate is outside its validity period" ;;
        "$VERIFY_UNTRUSTED_ROOT") why="the whole chain arrived and its root is not a trust anchor here" ;;
        "$VERIFY_NO_ISSUER")  why="only the leaf arrived; the certificate that continues the chain was not sent" ;;
        "$VERIFY_HOSTNAME")   why="the name asked for is not one the certificate carries" ;;
        *)                    why="see X509_V_ERR for this code" ;;
    esac
    mark no "verify code ${code}: ${why}"
fi

if [ "$cstat" = "0" ]; then
    mark yes "curl fetched the site with verification on (exit 0)"
else
    mark no  "curl refused the certificate (exit ${cstat}): $( curl_message "$SERVER_NAME" )"
fi

if case "$body" in *"$SITE_MARKER"*) true ;; *) false ;; esac; then
    mark yes "the fetch returned the site marker ${SITE_MARKER}"
else
    mark no  "the fetch did not return the site marker"
    ins="$( curl_insecure "$SERVER_NAME" )"
    if case "$ins" in *"$SITE_MARKER"*) true ;; *) false ;; esac; then
        printf '  the same fetch with -k DOES return the marker, so the web service is fine\n'
        printf '  and the certificate is the only thing in the way.\n'
    fi
fi
echo

# ---------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "TRUSTED  ($pass checks passed)"
else
    echo "NOT TRUSTED  ($pass passed, $fail outstanding)"
    echo "The first unticked check is the earliest thing to fix: every later stage is read through it."
fi
