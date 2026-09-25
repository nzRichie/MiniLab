#!/bin/sh
# Starter config for the victim: one machine attacked at three layers from one
# address.
#
#   tcp/80    lighttpd, with a 128-deep listen backlog
#   tcp/5201  iperf3, so the admin can measure the link end to end
#   udp/53    BIND, authoritative for lab. and signed
#
# Three services on one host so a single measuring instrument covers all three,
# and so the contrast between the stages is about the resource each flood
# exhausts rather than about which machine was hit.
#
# NOTHING DEFENSIVE IS CONFIGURED HERE. Syncookies are off, the SYN backlog is
# 32, and no rate limit of any kind is set. All three are what the learner
# turns on in Part 2, and a reset puts them back.
set -eu

SERVER_IP="129.0.0.20"
PREFIXLEN=24
IF_INSIDE="129-S1"
GW="129.0.0.1"

DOCROOT="/var/www/localhost/htdocs"
LIGHTTPD_CONF="/etc/lighttpd/lighttpd.conf"
LISTEN_BACKLOG=128
RATE_LIMIT_CONF="/etc/bind/rate-limit.conf"

# --- addressing -----------------------------------------------------------
ip addr replace "${SERVER_IP}/${PREFIXLEN}" dev "$IF_INSIDE"
ip link set "$IF_INSIDE" up
ip route replace default via "$GW"

# --- the kernel knobs, at their undefended baseline -----------------------
#
# This container is --privileged, which is what makes /proc/sys writable, which
# is what lets the learner turn syncookies on at the moment the handout asks
# them to. Setting them here as well is what makes a reset mean something:
# after Part 2 the machine has syncookies on and possibly a backlog the learner
# changed while answering question 8.
#
# tcp_no_metrics_save is NOT set here. It is set at `docker run`, because the
# attack does not deny service without it: the kernel exempts a peer it holds
# TCP metrics for from the pre-emptive SYN drop, the admin's own probe makes the
# admin exactly such a peer, and `ip tcp_metrics flush` returns EPERM under a
# rootless daemon.
sysctl -qw net.ipv4.tcp_syncookies=0
sysctl -qw net.ipv4.tcp_max_syn_backlog=32

# --- the web service ------------------------------------------------------
mkdir -p "$DOCROOT" /var/log/lighttpd
cat > "$DOCROOT/index.html" <<'HTML'
<html><head><title>lab service</title></head>
<body><h1>129.0.0.20</h1><p>The service this lab attacks. It is up.</p></body></html>
HTML
# A 100 kB object, so a transfer can be timed as well as counted. A fetch of the
# page above is small enough to survive a congested link; this one is not, and
# the difference between those two facts is question 18.
dd if=/dev/zero of="$DOCROOT/report.bin" bs=1024 count=100 2>/dev/null
chmod 644 "$DOCROOT/index.html" "$DOCROOT/report.bin"

# server.listen-backlog = 128 is load-bearing and is not tuning. lighttpd's
# stock backlog is 1024, deeper than tcp_max_syn_backlog, so the accept queue
# never overflows, the kernel never issues a syncookie, and Stage 2's mitigation
# works for a reason other than the one it is named for. At 128 cookies are
# genuinely issued and SyncookiesSent is a number the learner can read.
if ! grep -q 'server.listen-backlog' "$LIGHTTPD_CONF"; then
    printf '\nserver.listen-backlog = %d\n' "$LISTEN_BACKLOG" >> "$LIGHTTPD_CONF"
fi
chown -R lighttpd:lighttpd /var/log/lighttpd
if [ -f /run/lighttpd.pid ]; then kill "$( cat /run/lighttpd.pid )" 2>/dev/null || true; fi
pkill -x lighttpd 2>/dev/null || true
i=0
while [ "$i" -lt 50 ]; do
    netstat -tln 2>/dev/null | grep -q ':80 ' || break
    i=$(( i + 1 )); sleep 0.1
done
lighttpd -f "$LIGHTTPD_CONF"

# --- the throughput service -----------------------------------------------
#
# The server keeps its own log. A client measuring a link that is 95 % congested
# does not always get its own result back: the summary travels over the control
# connection, which crosses the same congested link, and under load iperf3 has
# been seen to exit without printing one at all. The server writes what it
# received either way, so /var/log/iperf3.log is the reading of last resort.
pkill -x iperf3 2>/dev/null || true
sleep 0.2
: > /var/log/iperf3.log
chmod 644 /var/log/iperf3.log
iperf3 -s -D --logfile /var/log/iperf3.log >/dev/null 2>&1 || true

# --- the authoritative name server ----------------------------------------
mkdir -p /var/bind /var/run/named
chmod 755 /var/bind /var/run/named

# The zone. Two names exist in it: the server itself and www. Everything else
# under lab. does not exist, which is the whole of Stage 3's attack surface.
cat > /var/bind/lab.zone <<'ZONE'
$TTL 300
@       IN  SOA ns.lab. hostmaster.lab. (
                2026092401  ; serial
                3600        ; refresh
                600         ; retry
                1209600     ; expire
                300 )       ; negative caching TTL
@       IN  NS  ns.lab.
ns      IN  A   129.0.0.20
www     IN  A   129.0.0.20
ZONE
chmod 644 /var/bind/lab.zone

# Response rate limiting lives in its own file, included from options{} below,
# and starts empty. Part 2 writes the rate-limit block into this file and runs
# `rndc reload`; a reset empties it again.
cat > "$RATE_LIMIT_CONF" <<'RL'
// Response rate limiting goes here. Nothing is configured: every response this
// server can produce, it produces, as fast as it can produce it.
RL
chmod 644 "$RATE_LIMIT_CONF"

cat > /etc/bind/named.conf <<'CONF'
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    // Authoritative only. This server answers for the one zone it holds and
    // refuses everything else, which is what an authoritative server does.
    recursion no;
    // Nothing this server looks up is signed by anybody else, so there is no
    // chain to validate and no trust anchor to load.
    dnssec-validation no;
    // Part 2's Stage 3 mitigation. Empty until the learner writes it.
    include "/etc/bind/rate-limit.conf";
};

logging {
    channel lab_log {
        file "/var/log/named.log" versions 3 size 5m;
        severity info;
        print-time yes;
        print-category yes;
    };
    category default        { lab_log; };
    category general        { lab_log; };
    // Every rate-limit drop is logged with the client address, the name it
    // asked for and the prefix the limit was applied to. That is Stage 3's
    // evidence. The `queries` category is deliberately NOT logged: at 240
    // queries a second a flood writes twenty thousand lines a run, which costs
    // the victim's own CPU and buries the lines worth reading.
    category rate-limit     { lab_log; };
    category dnssec         { lab_log; };
    // An authoritative server with recursion off still primes itself against
    // the root at startup, and on an isolated network that attempt fails with
    // "network unreachable resolving './NS/IN'". It is harmless and it is the
    // first thing in the log, where it would be the first thing a learner sent
    // to read this file finds. Discarded here rather than explained there.
    category resolver       { null; };
    category lame-servers   { null; };
    category cname          { null; };
};

zone "lab" {
    type primary;
    file "/var/bind/lab.zone";
    // One line signs the zone. BIND generates its own keys on first load and
    // rolls them on its own schedule, so nothing in this lab manages a key.
    // The zone is signed because a signed denial of existence is what makes a
    // question about a name that does not exist expensive to answer: 357 to 513
    // bytes against a 77-byte query, where an unsigned one is 122.
    dnssec-policy default;
    inline-signing yes;
};
CONF
chmod 644 /etc/bind/named.conf

# Restart named cleanly. The journal and the signed-zone backup are removed
# first: they hold a serial from the previous run, and a rewritten zone file
# with a lower serial than the journal's is a zone named refuses to load. The
# keys are kept, so a reset does not resign the zone from scratch.
if [ -f /var/run/named/named.pid ]; then kill "$( cat /var/run/named/named.pid )" 2>/dev/null || true; fi
pkill -x named 2>/dev/null || true
i=0
while [ "$i" -lt 50 ]; do
    netstat -uln 2>/dev/null | grep -q ':53 ' || break
    i=$(( i + 1 )); sleep 0.1
done
rm -f /var/bind/lab.zone.jnl /var/bind/lab.zone.jbk /var/bind/lab.zone.signed \
      /var/bind/lab.zone.signed.jnl /var/bind/named.stats
: > /var/log/named.log
named -c /etc/bind/named.conf

# Wait until the zone is loaded and signed before reporting up, so a spawn that
# returns is a spawn whose next command can query this server.
i=0
while [ "$i" -lt 60 ]; do
    if dig +short +time=1 +tries=1 @127.0.0.1 www.lab A 2>/dev/null | grep -q 129.0.0.20; then
        break
    fi
    i=$(( i + 1 )); sleep 0.5
done

echo "server: ${SERVER_IP} up. web tcp/80 (listen backlog ${LISTEN_BACKLOG}), iperf3 tcp/5201,"
echo "server: BIND authoritative for lab. (signed), syncookies off, syn backlog 32, no rate limit"
