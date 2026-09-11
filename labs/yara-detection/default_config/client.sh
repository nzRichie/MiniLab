#!/bin/sh
# Starter config for client: the machine that posts a file to the scanner.
#
# It arrives with the two uploads installed from the image into /root/uploads,
# so a learner who deleted or truncated one gets the original back on a reset.
# The two files are the whole of what this machine does.
set -eu

PREFIXLEN=24
CLIENT_IP="126.0.0.30"
LAN_IF="126-lan"

UPLOAD_DIR="/root/uploads"
UPLOAD_PRISTINE="/usr/local/share/minilabs/uploads"

ip addr replace "${CLIENT_IP}/${PREFIXLEN}" dev "$LAN_IF"
ip link set "$LAN_IF" up

rm -rf "$UPLOAD_DIR"
mkdir -p "$UPLOAD_DIR"
cp "$UPLOAD_PRISTINE"/*.exe "$UPLOAD_DIR/"
chmod 755 "$UPLOAD_DIR"
chmod 444 "$UPLOAD_DIR"/*.exe

echo "client: addressed ${CLIENT_IP}, uploads staged in ${UPLOAD_DIR}"
