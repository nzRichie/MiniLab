#!/bin/sh
# The forward proxy profile: tinyproxy on tcp/3128.
#
# An open proxy makes a connection on behalf of whoever asks it to, which means a
# machine that can reach it can reach whatever it can reach. It is a route rather
# than a secret, and it is the one unlock on this range that needs no credential
# at all: `curl -x <proxy> http://<somewhere>/` and the request goes out with the
# proxy's source address, not the learner's.
#
# It identifies itself twice over. Its own error pages carry a Server header with
# its exact release, and every response it relays carries a Via header naming it,
# which is how a proxy in the path is spotted from the client side.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the proxy profile"

conf=/etc/tinyproxy/lab.conf
mkdir -p /etc/tinyproxy
# StartServers is deliberately absent: this release logs "obsolete config item"
# for it on every start, in the middle of the spawn's output, for a setting it
# then ignores.
cat > "$conf" <<CONF
Port $port
Listen 0.0.0.0
Timeout 120
MaxClients 20
Allow 0.0.0.0/0
CONF

pkill -x tinyproxy 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x tinyproxy >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
tinyproxy -c "$conf" >/dev/null 2>&1 || die "tinyproxy failed to start on $port"
wait_listening tcp "$port" || die "tinyproxy is not listening on $port"

# A request the proxy cannot forward comes back as its own error page, and that
# page carries the Server header with the release in it.
banner="$( printf 'GET / HTTP/1.0\r\n\r\n' | nc -w 3 127.0.0.1 "$port" 2>/dev/null \
           | sed -n 's/^[Ss]erver: *//p' | tr -d '\r' | head -1 )"
# `squid-http` is in the accept list because that is the name nmap's own service
# database puts against port 3128, and a learner who reports what their tool
# printed is not wrong about the port. What the tool does not give them is the
# release, which is in the Server header and is what the version mark is for.
describe tcp "$port" proxy "$( version_digits "$banner" )" \
    proxy http-proxy tinyproxy squid-http

intel open-proxy
echo "profile proxy: up"
