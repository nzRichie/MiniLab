#!/bin/sh
# Starter config for the loader: the operator's payload host. It serves two
# files over plain HTTP and nothing else.
#
#   bot.py     the payload a recruited host fetches and runs. It is copied out
#              of the image's own /usr/local/lib/minilabs/bot.py, so the byte a
#              learner fetches is the byte in the image; selftest.sh checks the
#              two are identical.
#   words.txt  the wordlist the distributed guessing task pulls and splits
#              across the population.
#
# The access log is the recruitment record. It is the only place that says, in
# order, which hosts fetched the payload and when, which is what Part 2's
# questions read and what Part 4's last question turns on. lighttpd's combined
# log writes the client address and the request line, which is all those
# questions need.
set -eu

LOADER_IP="128.2.0.40"
PREFIXLEN=24
OP_IF="128-S3"
OP_GW="128.2.0.1"
DOCROOT="/var/www/localhost/htdocs"
ACCESS_LOG="/var/log/lighttpd/access.log"

# --- addressing -----------------------------------------------------------
ip addr replace "${LOADER_IP}/${PREFIXLEN}" dev "$OP_IF"
ip link set "$OP_IF" up
ip route replace default via "$OP_GW"

# --- the served files -----------------------------------------------------
mkdir -p "$DOCROOT"
cp /usr/local/lib/minilabs/bot.py "$DOCROOT/bot.py"
chmod 644 "$DOCROOT/bot.py"

# The wordlist, in the order lib.sh defines. Kept in step with WORDLIST there;
# the guessable password is entry 36. Written here rather than baked into the
# image so a change to the list is one edit in this file plus lib.sh, not an
# image rebuild.
cat > "$DOCROOT/words.txt" <<'WORDS'
summer2019
Password1
letmein
harbour
Harbour2019
admin123
opsadmin
changeme
Autumn-2020
qwerty123
Server!2020
welcome1
P@ssw0rd
Marsh-2018
kestrel
Kestrel2018
backup2019
Ops-Team-1
Winter-2021
trustno1
Harbour-2018
Sysops-9
monitoring
Kestrel-Marsh
Kestrel-Marsh-86
lighttpd
Marsh-88
Harbour-2020
Spring-2022
Kestrel-88
opsadmin2019
Quarry-1
Marsh-Kestrel-88
Kestrel_Marsh_88
kestrel-marsh-88
Kestrel-Marsh-88
Lintel-2021
Tarn-1990
Foxglove-1
Vault-7731
WORDS
chmod 644 "$DOCROOT/words.txt"

# --- the access log, and lighttpd -----------------------------------------
# The log is emptied on every run so the recruitment counts in Status and the
# order the questions read start from this spawn, not from yesterday's. lighttpd
# drops privileges to the lighttpd user after binding, so the log directory and
# the file are owned by that user; a root-owned log gives "opening log failed:
# Permission denied" and lighttpd exits.
mkdir -p /var/log/lighttpd
: > "$ACCESS_LOG"
chown -R lighttpd:lighttpd /var/log/lighttpd
chmod 644 "$ACCESS_LOG"

# The stock lighttpd.conf serves the docroot but does not enable the access log
# by default on this image. Add it once, idempotently.
CONF="/etc/lighttpd/lighttpd.conf"
if ! grep -q 'mod_accesslog' "$CONF"; then
    printf '\nserver.modules += ( "mod_accesslog" )\naccesslog.filename = "%s"\n' \
        "$ACCESS_LOG" >> "$CONF"
fi

if [ -f /run/lighttpd.pid ]; then kill "$( cat /run/lighttpd.pid )" 2>/dev/null || true; fi
pkill -x lighttpd 2>/dev/null || true
i=0
while [ "$i" -lt 50 ]; do
    netstat -tln 2>/dev/null | grep -q ':80 ' || break
    i=$(( i + 1 )); sleep 0.1
done
lighttpd -f "$CONF"

echo "loader: ${LOADER_IP} serving bot.py and words.txt, access log reset"
