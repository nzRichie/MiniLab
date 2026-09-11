#!/bin/sh
# The message broker profile: mosquitto on tcp/1883, accepting anonymous clients.
#
# MQTT is what the sensors and controllers on a building network talk, and a
# broker with `allow_anonymous true` hands its whole traffic to any client that
# subscribes. Subscribing to `#` is subscribing to every topic there is, and
# retained messages mean a client that connects long after a publisher has gone
# still receives the last value on every topic.
#
# The retained messages here are telemetry, which is to say an inventory: the
# topic names say which machines exist and what they are, and on some ranges one
# of the values is a secret that was published to a topic because publishing was
# easier than a configuration file.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the mqtt profile"
SECRET="$( param mqtt_secret )"
SECRET_KIND="$( param mqtt_secret_kind )"

conf=/etc/mosquitto/lab.conf
mkdir -p /etc/mosquitto
# The broker drops to its own unprivileged account before it opens its pid file
# and its log, so both have to live somewhere that account can write. Left in
# /run and /var/log it starts, drops privilege, fails with "Unable to write pid
# file" and exits, which reads as a broker that would not bind the port.
mkdir -p /run/mosquitto /var/log/mosquitto
chown mosquitto:mosquitto /run/mosquitto /var/log/mosquitto 2>/dev/null || true
chmod 755 /run/mosquitto /var/log/mosquitto
cat > "$conf" <<CONF
listener $port 0.0.0.0
allow_anonymous true
persistence false
log_dest file /var/log/mosquitto/lab.log
pid_file /run/mosquitto/lab.pid
CONF

pkill -x mosquitto 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x mosquitto >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
mosquitto -c "$conf" -d >/dev/null 2>&1 || die "mosquitto failed to start on $port"
wait_listening tcp "$port" || die "mosquitto is not listening on $port"

P="mosquitto_pub -h 127.0.0.1 -p $port -r"
$P -t "${ORG_PREFIX}/site" -m "$( org_site 1 )" >/dev/null 2>&1
$P -t "${ORG_PREFIX}/plant/temp" -m "21.4" >/dev/null 2>&1
$P -t "${ORG_PREFIX}/plant/door" -m "closed" >/dev/null 2>&1
$P -t "${ORG_PREFIX}/ops/notice" \
   -m "nightly job runs 0200; contact ${ORG_TEAM}" >/dev/null 2>&1
case "$SECRET_KIND" in
    passphrase) $P -t "${ORG_PREFIX}/ops/backup-key" -m "passphrase ${SECRET}" >/dev/null 2>&1 ;;
    filename)   $P -t "${ORG_PREFIX}/ops/archive" -m "${SECRET}" >/dev/null 2>&1 ;;
esac

# The broker sends no version. A CONNACK carries a return code and nothing about
# the software, and nmap reports the service and not a release, so nothing is
# recorded and nothing is graded.
describe tcp "$port" mqtt "" mqtt mosquitto

intel mqtt-open
echo "profile mqtt: up"
