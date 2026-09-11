#!/bin/sh
# Starter config for the certificate authority.
#
# It leaves the machine able to run a CA and holding no CA at all: the directory
# skeleton, the two databases, the two serial counters and the configuration file
# that names them are here, and every key and every certificate is missing. The
# learner creates all of those in Part 2 and Part 3, which is what "runs a
# certificate authority" has to mean if it is going to be graded.
#
# What this script does provide is the openssl.cnf. That is deliberate and it is
# the one thing in the lab handed over rather than built: an openssl CA
# configuration is sixty lines of section names, and typing it is not what the
# lab teaches. The handout reads the sections the learner's commands actually
# select, and one question is answered from this file.
#
# Everything is written to survive a second run, because reset.sh re-runs this
# script to rebuild the baseline: the CA tree is deleted and recreated, and the
# SSH key pair the server and the client authenticate with is regenerated only
# when it is missing, because the other two containers hold a copy of it that
# this script cannot reach.
set -eu

# Values restated from scripts/lib.sh; this runs inside the container, where
# lib.sh does not exist. Change them in both places or not at all.
PREFIXLEN=24
CA_IP="111.0.0.10"
SERVER_IP="111.0.0.20"
CLIENT_IP="111.0.0.30"
HOST_IF="111-S1"

CA_DIR="/root/ca"
SSH_KEY="/root/.ssh/lab_key"

# ---------------------------------------------------------------------------
# 1. Address the one interface. Flat /24, no gateway: every host in this lab is
#    one hop away and nothing here routes.
ip addr flush dev "$HOST_IF" 2>/dev/null || true
ip addr add "${CA_IP}/${PREFIXLEN}" dev "$HOST_IF"
ip link set dev "$HOST_IF" up

# Names for the other two machines, so the handout can write `scp ... server:`
# rather than an address. The CA never initiates either transfer, but a name in
# `openssl ca`'s output and in the log is easier to read than an address.
grep -q "$SERVER_IP" /etc/hosts 2>/dev/null || {
    echo "$SERVER_IP server www.minilabs.lab" >> /etc/hosts
    echo "$CLIENT_IP client"                  >> /etc/hosts
}

# ---------------------------------------------------------------------------
# 2. The CA tree. Two tiers, each with its own private key, its own database of
#    what it has issued and its own serial counter.
#
#    index.txt is the database and it starts empty; `openssl ca` refuses to run
#    without the file existing, and appends one line per certificate it issues.
#    serial holds the number the next certificate will carry, in hex, and
#    `openssl ca` increments it after each issuance.
rm -rf "$CA_DIR"
mkdir -p "$CA_DIR/root/private" "$CA_DIR/root/certs" "$CA_DIR/root/newcerts" \
         "$CA_DIR/int/private"  "$CA_DIR/int/certs"  "$CA_DIR/int/newcerts" \
         "$CA_DIR/int/csr"

# A private key directory readable by anyone but its owner is the single most
# common way a CA stops being one. chmod rather than relying on the umask:
# `docker exec` runs with umask 0022 under a rootful daemon and 0000 under a
# rootless one, so a bare mkdir gives 755 on one and 777 on the other.
chmod 700 "$CA_DIR/root/private" "$CA_DIR/int/private"
chmod 755 "$CA_DIR" "$CA_DIR/root" "$CA_DIR/int" \
          "$CA_DIR/root/certs" "$CA_DIR/root/newcerts" \
          "$CA_DIR/int/certs"  "$CA_DIR/int/newcerts" "$CA_DIR/int/csr"

: > "$CA_DIR/root/index.txt"
: > "$CA_DIR/int/index.txt"
echo 1000 > "$CA_DIR/root/serial"
echo 2000 > "$CA_DIR/int/serial"

# ---------------------------------------------------------------------------
# 3. The configuration file both tiers are driven from.
#
#    `openssl ca` reads exactly one section, named by default_ca or overridden
#    with -name, and everything it needs is in that section: which key signs,
#    which certificate that key belongs to, where issued certificates and the
#    database live, and which fields of a request it will accept.
#
#    Neither section sets rand_serial, and that absence is load-bearing rather
#    than an omission. Setting it to `no` does not turn random serials off:
#    OpenSSL 3.1's `ca` app switches to a random 159-bit serial whenever the key
#    is present in the section at all, whatever value follows it, and the serial
#    file is then never read and never incremented. Measured on OpenSSL 3.1.8:
#    with `rand_serial = no` the issued serial was a 20-byte random value and the
#    file still read 2000; with the line deleted the issued serial was 2000 and
#    the file advanced to 2001. Leaving it out is what lets the learner read the
#    counter move.
#
#    unique_subject = no matters in Part 4: the learner issues three certificates
#    carrying the same subject on purpose, and the default would refuse the
#    second one.
cat > "$CA_DIR/openssl.cnf" <<'CNF'
# MiniLabs private CA. Two authorities in one file: `-name root_ca` selects the
# offline root, and the default selects the issuing intermediate.

[ ca ]
default_ca = int_ca

# --------------------------------------------------------------------------
# The root. It signs one thing in its life: the intermediate's certificate.
[ root_ca ]
dir               = /root/ca/root
certs             = $dir/certs
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
private_key       = $dir/private/root.key
certificate       = $dir/certs/root.crt
default_md        = sha256
policy            = policy_loose
email_in_dn       = no
unique_subject    = no
copy_extensions   = none
preserve          = no

# --------------------------------------------------------------------------
# The intermediate. It signs every server certificate the lab issues.
[ int_ca ]
dir               = /root/ca/int
certs             = $dir/certs
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
private_key       = $dir/private/int.key
certificate       = $dir/certs/int.crt
default_md        = sha256
policy            = policy_loose
email_in_dn       = no
unique_subject    = no
copy_extensions   = none
preserve          = no

# Which fields of a request's subject this CA will accept. `supplied` means the
# request has to carry one; `optional` means it may. copy_extensions is none, so
# a request cannot talk this CA into any extension at all: whatever the issued
# certificate carries, the CA put there.
[ policy_loose ]
commonName             = supplied
countryName            = optional
stateOrProvinceName    = optional
organizationName       = optional
organizationalUnitName = optional
emailAddress           = optional

# --------------------------------------------------------------------------
# Defaults for `openssl req`, which generates keys and writes signing requests.
[ req ]
default_md         = sha256
distinguished_name = req_dn
prompt             = no
string_mask        = utf8only

[ req_dn ]
CN = MiniLabs

# --------------------------------------------------------------------------
# Extension sets. Which one applies is chosen on the command line with
# -extensions, and it decides what the issued certificate is allowed to do.

# The root: an authority, allowed to sign certificates and revocation lists and
# nothing else. critical on basicConstraints means a client that does not
# understand the extension must reject the certificate rather than ignore it.
[ v3_root_ca ]
subjectKeyIdentifier   = hash
basicConstraints       = critical, CA:true
keyUsage               = critical, keyCertSign, cRLSign

# The intermediate: an authority too, but pathlen:0 caps the chain below it. It
# may issue end-entity certificates and it may not issue another authority.
[ v3_intermediate_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
basicConstraints       = critical, CA:true, pathlen:0
keyUsage               = critical, keyCertSign, cRLSign
CNF
chmod 644 "$CA_DIR/openssl.cnf"

# ---------------------------------------------------------------------------
# 4. SSH, so the server can hand this machine a signing request and collect the
#    certificate back, and the client can collect the root certificate.
#
#    Key authentication only. A CA that accepts a password over the network is a
#    worse example than no CA at all, and the learner never types one.
ssh-keygen -A >/dev/null 2>&1
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Generated once and left alone afterwards: the server and the client hold the
# private half, and this script has no way to reach into those containers and
# replace it. reset.sh re-runs this file, so regenerating here would lock both of
# them out of the CA with no error the learner could interpret.
if [ ! -f "$SSH_KEY" ]; then
    ssh-keygen -t ed25519 -N '' -C 'minilabs private-ca lab' -f "$SSH_KEY" >/dev/null
fi
cp "${SSH_KEY}.pub" /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys "$SSH_KEY"
chmod 644 "${SSH_KEY}.pub"

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/'      /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/'       /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/'          /etc/ssh/sshd_config

# Stop before start, so a second run replaces the daemon rather than failing to
# bind. The pid file is the only reliable handle: this container's PID 1 is
# `sleep infinity`, and `pgrep -x sshd` lists per-connection children alongside
# the listener.
[ -f /run/sshd.pid ] && kill "$(cat /run/sshd.pid)" 2>/dev/null || true
sleep 0.2
/usr/sbin/sshd -e >/dev/null 2>&1

echo "ca: CA tree at $CA_DIR is empty and ready; no key and no certificate exist yet"
