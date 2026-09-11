#!/bin/sh
# Starter config for the web server.
#
# It leaves the machine doing what a great many real deployments do: serving the
# site over TLS with a certificate it signed for itself. Nothing is broken, the
# handshake completes, the content arrives, and every client that checks the
# certificate refuses it. Part 1 is the learner finding out what that refusal
# looks like and what number it carries.
#
# So the delivered state is a working service with a certificate nobody can
# verify, and the learner's job across Parts 2 to 4 is to replace it with one an
# authority issued, without touching the content the service serves.
#
# Everything is written to survive a second run, because reset.sh re-runs this
# script to rebuild the baseline: the whole TLS directory is deleted and the
# self-signed certificate is regenerated, so a learner who has issued three
# certificates and edited the config four times gets the delivered state back.
set -eu

# Values restated from scripts/lib.sh; this runs inside the container, where
# lib.sh does not exist. Change them in both places or not at all.
PREFIXLEN=24
SERVER_IP="111.0.0.20"
CA_IP="111.0.0.10"
CLIENT_IP="111.0.0.30"
HOST_IF="111-S1"

SERVER_NAME="www.minilabs.lab"
SITE_MARKER="PRIVATE-CA-SITE-7F2C91"
WEB_ROOT="/var/www/localhost/htdocs"

SRV_TLS_DIR="/etc/lighttpd/tls"
SELF_CRT="${SRV_TLS_DIR}/selfsigned.crt"
SELF_KEY="${SRV_TLS_DIR}/selfsigned.key"
LIGHTTPD_CONF="/etc/lighttpd/lighttpd.conf"
LIGHTTPD_PID="/run/lighttpd.pid"
HTTPS_PORT=443

# ---------------------------------------------------------------------------
# 1. Address the one interface, and name the CA so the handout can write
#    `scp ... ca:` rather than an address.
ip addr flush dev "$HOST_IF" 2>/dev/null || true
ip addr add "${SERVER_IP}/${PREFIXLEN}" dev "$HOST_IF"
ip link set dev "$HOST_IF" up

grep -q "$CA_IP" /etc/hosts 2>/dev/null || {
    echo "$CA_IP ca"         >> /etc/hosts
    echo "$CLIENT_IP client" >> /etc/hosts
}

# The private key of the SSH pair the CA accepts. spawn.sh copies it in after
# this script has run; what this script provides is the client configuration
# around it, so the learner's first `scp` neither prompts nor fails.
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat > /root/.ssh/config <<'SSHCFG'
Host ca
    User root
    IdentityFile /root/.ssh/lab_key
    StrictHostKeyChecking accept-new
    UserKnownHostsFile /root/.ssh/known_hosts
    LogLevel ERROR
SSHCFG
chmod 600 /root/.ssh/config

# ---------------------------------------------------------------------------
# 2. The content. One file with one marker in it, so a fetch that returns the
#    marker is unambiguous evidence that the web service answered rather than
#    something else on the address. The learner never edits this: the whole lab
#    is about whether the client will accept the certificate wrapped around it.
mkdir -p "$WEB_ROOT"
chmod 755 "$WEB_ROOT"
cat > "$WEB_ROOT/index.html" <<HTML
<!doctype html>
<title>MiniLabs internal site</title>
<h1>MiniLabs internal site</h1>
<p>$SITE_MARKER</p>
HTML
chmod 644 "$WEB_ROOT/index.html"

# ---------------------------------------------------------------------------
# 3. The certificate the machine is delivered with: generated here, signed with
#    its own key, with no authority anywhere behind it. It carries the right name
#    in subjectAltName, so the ONLY thing wrong with it is that nothing vouches
#    for it. That is what makes Part 1's verify code the one it is: a name
#    mismatch would mask it.
rm -rf "$SRV_TLS_DIR"
mkdir -p "$SRV_TLS_DIR"
chmod 755 "$SRV_TLS_DIR"

openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -noenc \
    -keyout "$SELF_KEY" -out "$SELF_CRT" \
    -subj "/CN=${SERVER_NAME}" \
    -addext "subjectAltName=DNS:${SERVER_NAME}" \
    -addext "basicConstraints=CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1

# A private key any account on the machine can read is not a private key. 600
# explicitly rather than by umask, which differs between a rootful and a rootless
# daemon.
chmod 600 "$SELF_KEY"
chmod 644 "$SELF_CRT"

# ---------------------------------------------------------------------------
# 4. lighttpd, terminating TLS on 443 with that certificate.
#
#    ssl.pemfile names the file the server sends to a client, and it may hold
#    more than one certificate; ssl.privkey names the key that proves the server
#    holds the first one. Part 3 changes the first of those two to a file with
#    two certificates in it, and Part 4 changes it back to a file with one, which
#    is the whole of that failure.
cat > "$LIGHTTPD_CONF" <<CONF
# MiniLabs private-CA lab. The learner edits ssl.pemfile and ssl.privkey and
# nothing else in this file.
server.document-root = "$WEB_ROOT"
server.pid-file      = "$LIGHTTPD_PID"
server.modules       = ( "mod_openssl" )
index-file.names     = ( "index.html" )
mimetype.assign      = ( ".html" => "text/html" )

\$SERVER["socket"] == ":${HTTPS_PORT}" {
    ssl.engine  = "enable"
    ssl.pemfile = "$SELF_CRT"
    ssl.privkey = "$SELF_KEY"
}
CONF
chmod 644 "$LIGHTTPD_CONF"

# Stop before start, so a second run replaces the daemon rather than failing to
# bind. pkill -x matches the process name exactly; a pattern match on the command
# line would match the shell this script runs in, whose own arguments contain the
# string.
pkill -x lighttpd 2>/dev/null || true
sleep 0.3
rm -f "$LIGHTTPD_PID"
lighttpd -f "$LIGHTTPD_CONF" >/dev/null 2>&1

echo "server: serving $SERVER_NAME on tcp/${HTTPS_PORT} with a certificate it signed itself"
