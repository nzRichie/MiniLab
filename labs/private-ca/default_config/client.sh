#!/bin/sh
# Starter config for the client.
#
# It leaves the machine with a stock trust store: the public certificate
# authorities its distribution ships, and nothing else. That is the whole point
# of the delivered state. Every certificate in this lab is issued by an authority
# no distribution has ever heard of, so until the learner installs the root
# certificate in Part 3, this machine refuses everything the server presents.
#
# The one thing it is given is the name-to-address mapping, in /etc/hosts. Name
# resolution is not what this lab teaches, and a DNS server would be a fourth
# container answering a question nobody here asks. What matters is only that the
# client asks for a NAME rather than an address, because a name is what a
# certificate carries and what a client checks the certificate against.
#
# Everything is written to survive a second run, because reset.sh re-runs this
# script to rebuild the baseline: the anchor the learner installed is removed and
# the trust bundle is rebuilt without it.
set -eu

# Values restated from scripts/lib.sh; this runs inside the container, where
# lib.sh does not exist. Change them in both places or not at all.
PREFIXLEN=24
CLIENT_IP="111.0.0.30"
SERVER_IP="111.0.0.20"
CA_IP="111.0.0.10"
HOST_IF="111-S1"

SERVER_NAME="www.minilabs.lab"
WRONG_NAME="store.minilabs.lab"
TRUST_ANCHOR="/usr/local/share/ca-certificates/minilabs-root.crt"

# ---------------------------------------------------------------------------
# 1. Address the one interface.
ip addr flush dev "$HOST_IF" 2>/dev/null || true
ip addr add "${CLIENT_IP}/${PREFIXLEN}" dev "$HOST_IF"
ip link set dev "$HOST_IF" up

# ---------------------------------------------------------------------------
# 2. Name resolution, such as it is.
#
#    www.minilabs.lab resolves to the server. store.minilabs.lab deliberately
#    does NOT resolve: Part 4 issues a certificate for it and serves that
#    certificate from the server, and the failure has to be between the name the
#    client asked for and the name the certificate carries. If the second name
#    resolved anywhere, a learner could reach it and never see the mismatch.
sed -i "/$SERVER_NAME/d" /etc/hosts 2>/dev/null || true
{
    echo "$SERVER_IP $SERVER_NAME"
    echo "$CA_IP ca"
} >> /etc/hosts

# The private key of the SSH pair the CA accepts, so the client can collect the
# root certificate from the authority that issued it rather than from the server
# presenting it. spawn.sh copies the key in after this script has run.
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
# 3. A stock trust store. Any anchor a previous run of this lab installed is
#    removed and the bundle is rebuilt, so the client starts each time trusting
#    exactly what the distribution shipped and nothing the learner added.
rm -f "$TRUST_ANCHOR"
update-ca-certificates >/dev/null 2>&1 || true

echo "client: trust store holds only the public authorities Alpine ships"
