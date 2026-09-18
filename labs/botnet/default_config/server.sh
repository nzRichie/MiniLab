#!/bin/sh
# Starter config for the inside server: the machine the population is eventually
# tasked against. It runs a web service and an SSH service, and it holds the two
# accounts the rest of the lab turns on.
#
#   opsadmin   the account the distributed guessing task is aimed at. Its
#              password is one entry of the wordlist the loader serves, so the
#              population can find it; it is a plain user account.
#   sysops     the maintenance account the admin workstation logs in with every
#              minute. Its password is on no wordlist, so the botnet never
#              reaches it and a defender changing what the botnet guesses never
#              breaks it. It is the reason tcp/22 toward this server cannot
#              simply be switched off.
#
# The web service and the SSH service are both here because Part 4's graded end
# state has to keep the web page reachable from anywhere while it shuts the
# guessing down, so both have to be real and both have to be observed.
set -eu

SERVER_IP="128.0.0.20"
PREFIXLEN=24
INSIDE_IF="128-S1"
INSIDE_GW="128.0.0.1"

SERVER_USER="opsadmin"
SERVER_PW="Kestrel-Marsh-88"
ROOT_PW="Quarry-Lintel-5540"
SYSOPS_USER="sysops"
SYSOPS_PW="Foxglove-Tarn-6182"

AUTH_LOG="/var/log/minilabs-sshd.log"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_PID="/run/sshd.pid"
DOCROOT="/var/www/localhost/htdocs"

# --- addressing -----------------------------------------------------------
ip addr replace "${SERVER_IP}/${PREFIXLEN}" dev "$INSIDE_IF"
ip link set "$INSIDE_IF" up
ip route replace default via "$INSIDE_GW"

# --- the web service ------------------------------------------------------
# lighttpd, unmodified. One page, so the admin's probe has something to fetch
# and the graded end state has something to keep reachable.
mkdir -p "$DOCROOT"
cat > "$DOCROOT/index.html" <<'HTML'
<!doctype html>
<title>Ops portal</title>
<h1>Internal operations portal</h1>
<p>Authorised staff only.</p>
HTML
chmod 644 "$DOCROOT/index.html"

if [ -f /run/lighttpd.pid ]; then kill "$( cat /run/lighttpd.pid )" 2>/dev/null || true; fi
pkill -x lighttpd 2>/dev/null || true
i=0
while [ "$i" -lt 50 ]; do
    netstat -tln 2>/dev/null | grep -q ':80 ' || break
    i=$(( i + 1 )); sleep 0.1
done
lighttpd -f /etc/lighttpd/lighttpd.conf

# --- the accounts ---------------------------------------------------------
# opsadmin is an ordinary login account with a guessable password. sysops is the
# maintenance account: a separate password on no wordlist, so it survives every
# defence the learner writes against the guessing.
if ! id -u "$SERVER_USER" >/dev/null 2>&1; then adduser -D -s /bin/sh "$SERVER_USER"; fi
if ! id -u "$SYSOPS_USER"  >/dev/null 2>&1; then adduser -D -s /bin/sh "$SYSOPS_USER"; fi
echo "${SERVER_USER}:${SERVER_PW}" | chpasswd
echo "${SYSOPS_USER}:${SYSOPS_PW}" | chpasswd
echo "root:${ROOT_PW}" | chpasswd

# --- sshd -----------------------------------------------------------------
# Password logins on, so opsadmin can be guessed and sysops can be used. A
# pristine copy of the shipped config is kept and restored, so a reset returns
# the file to what Part 1 assumes rather than patching a learner's edits.
[ -f "${SSHD_CONFIG}.lab-orig" ] || cp "$SSHD_CONFIG" "${SSHD_CONFIG}.lab-orig"
cp "${SSHD_CONFIG}.lab-orig" "$SSHD_CONFIG"
sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' "$SSHD_CONFIG"
grep -q '^PasswordAuthentication yes' "$SSHD_CONFIG" || echo 'PasswordAuthentication yes' >> "$SSHD_CONFIG"
echo 'PermitRootLogin yes' >> "$SSHD_CONFIG"
ssh-keygen -A >/dev/null 2>&1 || true

# The auth log is half the lab's oracle. sshd -e sends its authentication log to
# stderr; redirecting stderr here gives a file whose every "Failed password"
# and "Accepted password" line carries the SOURCE ADDRESS, which is the field
# every rule in Part 4's first two moves is written against.
#
# A successful guess also has to be timestampable, so the run's time to
# compromise can be measured. sshd's own line has no epoch, so a helper marks
# the first accept for opsadmin from a field address with an epoch line the
# oracle reads.
if [ -f "$SSHD_PID" ]; then kill "$( cat "$SSHD_PID" )" 2>/dev/null || true; fi
pkill -x sshd 2>/dev/null || true
i=0
while [ "$i" -lt 50 ]; do
    netstat -tln 2>/dev/null | grep -q ':22 ' || break
    i=$(( i + 1 )); sleep 0.1
done
mkdir -p /var/log
: > "$AUTH_LOG"
chmod 644 "$AUTH_LOG"
# -D keeps sshd in the foreground so the redirect below captures every
# connection's log; without it sshd daemonizes and its per-connection auth lines
# (the "Failed password" and "Accepted password from <addr>" this lab's oracle
# reads) detach from this stderr and vanish. -e sends the log to stderr. It is
# backgrounded here so the starter script returns.
/usr/sbin/sshd -D -e >>"$AUTH_LOG" 2>&1 &

# Watcher: prepend an epoch-stamped MINILABS-GUESSED line the first time
# opsadmin is accepted from a field address, so the oracle can time the
# compromise. It reads its own tail and exits after the first hit, so a reset
# that restarts sshd and re-runs this file does not leave two watchers behind.
WATCH_PID="/run/minilabs/guess-watch.pid"
mkdir -p /run/minilabs
if [ -f "$WATCH_PID" ]; then kill "$( cat "$WATCH_PID" )" 2>/dev/null || true; fi
(
    # Follow the log; on the first accept for opsadmin from 128.1.x, stamp it.
    tail -n0 -F "$AUTH_LOG" 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *"Accepted password for ${SERVER_USER} from 128.1."*)
                echo "$( date +%s ) MINILABS-GUESSED ${SERVER_USER}" >> "$AUTH_LOG"
                break ;;
        esac
    done
) &
echo $! > "$WATCH_PID"

echo "server: ${SERVER_IP} web+ssh up, ${SERVER_USER} guessable, ${SYSOPS_USER} maintenance"
