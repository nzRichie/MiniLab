#!/bin/sh
# Starter config for ext2: the other host standing in for the internet.
#
# It carries two of the five outside addresses at spawn, and they are not the
# same kind of thing:
#
#   118.1.0.20  the monitoring endpoint every workstation polls. Legitimate, and
#               polled on exactly the period the implant checks in on, which is
#               what stops "repeats regularly" from identifying anything by
#               itself.
#   118.1.0.66  the controller. It answers a check-in on tcp/8080 in plain HTTP
#               and on tcp/443 over TLS, from one process, so moving the implant
#               from one to the other changes nothing on this side.
#
# advance.sh adds a third address here when the incident reaches stage 3. It is
# not configured at spawn on purpose: an address that exists from the start is
# an address a learner can find before the stage that introduces it.
#
# Splitting the five outside addresses one-legitimate-with-the-controller and
# two-legitimate-elsewhere is deliberate. It means working out which container
# an address belongs to tells a learner nothing about which address is the
# controller.
#
# It is idempotent: reset.sh re-runs it, and it clears the check-in log so a
# fresh run starts from an empty record.
set -eu

PREFIXLEN=24
HEALTH_IP="118.1.0.20"
C2_IP="118.1.0.66"
GW_OUTSIDE_IP="118.1.0.1"
EXT_IF="118-ext"

C2_HTTP_PORT=8080
C2_TLS_PORT=443
C2_LOG="/var/log/c2/checkins.log"
C2_CERT="/etc/minilabs/c2.pem"
C2_REPLY_BYTES=64

HEALTH_ROOT="/var/www/health"
HEALTH_CONF="/etc/lighttpd/health.conf"
HEALTH_PID="/run/lighttpd-health.pid"

ip addr replace "${HEALTH_IP}/${PREFIXLEN}" dev "$EXT_IF"
ip addr replace "${C2_IP}/${PREFIXLEN}" dev "$EXT_IF"
ip link set "$EXT_IF" up
ip route replace default via "$GW_OUTSIDE_IP"

# The stage-3 address, if a previous run left it behind. A reset puts the
# incident back to stage 1, and an address from stage 3 still on the interface
# would let a learner find it before the lab has introduced it.
ip addr del "118.1.0.99/${PREFIXLEN}" dev "$EXT_IF" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Kill anything this script started on a previous run before starting it again.
#
# The bracket in the pattern is load-bearing. `pkill -f c2listener.py` run from
# `sh -c` matches the shell running it as well, because that string is in the
# shell's own argv; the process would kill its own parent and the listener would
# sometimes survive. `[c]2listener` matches the running process and not the
# pattern itself.
pkill -f '[c]2listener\.py' 2>/dev/null || true
pkill -f '[h]ealth-body' 2>/dev/null || true

# ---------------------------------------------------------------------------
# The monitoring endpoint.
#
# /health is rewritten every five seconds with the current time and a drawn
# number of check entries, so consecutive replies differ in length by tens of
# bytes. That difference is one of the three things that separate this flow from
# the implant's, whose reply is the same 64 bytes every time, so it has to be
# real rather than described.
#
# The file is written to a temporary name and moved into place, because
# lighttpd serves it while the loop rewrites it and a reader that arrived
# mid-write would get a short file rather than a different one.
mkdir -p "$HEALTH_ROOT"
chmod 755 "$HEALTH_ROOT"
printf '{"status":"ok"}\n' > "${HEALTH_ROOT}/health"
chmod 644 "${HEALTH_ROOT}/health"

cat > /usr/local/bin/health-body <<'EOF'
#!/bin/sh
# Rewrite the monitoring endpoint's body every five seconds so that consecutive
# replies differ in length by tens of bytes rather than by one digit.
#
# The number of check entries is drawn as well as their values, because a body
# whose only variable part is a counter is the same length nearly every time,
# and "this destination's replies are all the same size" is one of the three
# things Part 2 asks the learner to measure. It has to be false for the
# legitimate endpoint and true for the controller.
#
# The variable fields are drawn from /dev/urandom rather than from `date +%N`,
# which is a GNU extension busybox does not carry: on Alpine that would expand
# to the literal characters %N and produce a constant length.
ROOT="$1"
NAMES="disk mem cpu queue net io swap conn"
while :; do
    r="$( od -An -N4 -tu4 < /dev/urandom | tr -dc '0-9' )"
    r="${r:-1}"
    n=$(( r % 6 + 1 ))
    body="{\"status\":\"ok\",\"t\":$( date +%s ),\"checks\":{"
    i=0
    for name in $NAMES; do
        i=$(( i + 1 ))
        [ "$i" -gt "$n" ] && break
        v="$( od -An -N4 -tu4 < /dev/urandom | tr -dc '0-9' )"
        [ "$i" -gt 1 ] && body="${body},"
        body="${body}\"${name}\":$(( ${v:-1} % 100000 ))"
    done
    printf '%s}}\n' "$body" > "${ROOT}/.health.tmp"
    mv "${ROOT}/.health.tmp" "${ROOT}/health"
    sleep 5
done
EOF
chmod 755 /usr/local/bin/health-body

# lighttpd here is bound to ONE address rather than to every address on the
# machine. Left unbound it would also answer on 118.1.0.66, and a controller
# that served a monitoring page on port 80 would be a confusing thing to hand a
# learner who is trying to work out what each address is.
cat > "$HEALTH_CONF" <<EOF
server.document-root = "${HEALTH_ROOT}"
server.bind          = "${HEALTH_IP}"
server.port          = 80
server.pid-file      = "${HEALTH_PID}"
index-file.names     = ( "health" )
mimetype.assign      = ( ".html" => "text/html", "" => "application/json" )
EOF

stop_and_wait() {   # <pid file> <process name> <port it must release>
    if [ -f "$1" ]; then
        kill "$( cat "$1" )" 2>/dev/null || true
    fi
    pkill -x "$2" 2>/dev/null || true
    i=0
    while [ "$i" -lt 50 ]; do
        netstat -tln 2>/dev/null | grep -q ":$3 " || return 0
        i=$(( i + 1 ))
        sleep 0.1
    done
    if [ -f "$1" ]; then kill -9 "$( cat "$1" )" 2>/dev/null || true; fi
    pkill -9 -x "$2" 2>/dev/null || true
    sleep 0.5
}

stop_and_wait "$HEALTH_PID" lighttpd 80
rm -f /var/log/lighttpd/access.log
lighttpd -f "$HEALTH_CONF"
setsid /usr/local/bin/health-body "$HEALTH_ROOT" >/dev/null 2>&1 &

# ---------------------------------------------------------------------------
# The controller.
#
# The certificate is generated here rather than baked into the image, so the
# private key never sits in a published layer. It is self-signed and nothing is
# told to trust it, which is why the implant passes -k; a learner who runs into
# the certificate at all in this lab is looking at stage 2, where TLS 1.3
# encrypts it and it is not visible in a capture anyway.
#
# -subj is given explicitly because openssl req prompts without it and this
# script runs with no terminal attached, so a missing -subj is a spawn that
# hangs rather than one that fails.
if [ ! -f "$C2_CERT" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
        -subj "/CN=node-7" \
        -keyout "$C2_CERT" -out "${C2_CERT}.crt" >/dev/null 2>&1
    cat "${C2_CERT}.crt" >> "$C2_CERT"
    rm -f "${C2_CERT}.crt"
    chmod 600 "$C2_CERT"
fi

mkdir -p "$( dirname "$C2_LOG" )"
chmod 755 "$( dirname "$C2_LOG" )"
: > "$C2_LOG"
chmod 644 "$C2_LOG"

setsid python3 /usr/local/lib/minilabs/c2listener.py \
    --http-port "$C2_HTTP_PORT" \
    --tls-port "$C2_TLS_PORT" \
    --cert "$C2_CERT" \
    --log "$C2_LOG" \
    --reply-bytes "$C2_REPLY_BYTES" >/dev/null 2>&1 &

# Give both listeners a moment to bind, so a spawn that goes straight on to
# starting the implant does not lose the first check-in to a refused connection.
i=0
while [ "$i" -lt 40 ]; do
    if netstat -tln 2>/dev/null | grep -q ":${C2_TLS_PORT} " \
       && netstat -tln 2>/dev/null | grep -q ":${C2_HTTP_PORT} "; then
        break
    fi
    i=$(( i + 1 ))
    sleep 0.25
done

echo "ext2: addressed ${HEALTH_IP} and ${C2_IP}, monitoring endpoint and controller listening"
