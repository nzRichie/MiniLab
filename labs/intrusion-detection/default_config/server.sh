#!/bin/sh
# Starter configuration for the server: the machine under attack, and the only
# one the learner configures.
#
# It arrives with three listeners, an empty filter table and no Suricata. The
# gap the learner closes is that the telnet service answers any address that can
# reach it, and nothing on the machine records that it did.
#
# reset.sh re-runs this script, so everything in it is idempotent and everything
# the learner may have added is removed here: the filter rules, the Suricata
# process, the local rules file, the edits to suricata.yaml, and the alert log.
set -e

ip addr flush dev 124-lan 2>/dev/null || true
ip addr add 124.0.0.10/24 dev 124-lan
ip link set 124-lan up
ip route replace default via 124.0.0.1

# --- the account the telnet service accepts --------------------------------
#
# Unprivileged on purpose. A shell as a service account is already the
# compromise this lab is written around, and privilege escalation is another
# lab's subject.
if ! id svcops >/dev/null 2>&1; then
    adduser -D svcops
fi
echo 'svcops:labpass' | chpasswd

# --- the three listeners ---------------------------------------------------
#
# Each is stopped before it is started, so a reset leaves exactly one of each
# rather than a second copy fighting for the port.
pkill -x telnetd  2>/dev/null || true
pkill -x sshd     2>/dev/null || true
pkill -x lighttpd 2>/dev/null || true
sleep 0.3

cat > /var/www/localhost/htdocs/index.html <<'HTML'
<!doctype html>
<html><head><title>Kaimai Freight</title></head>
<body>
<h1>Kaimai Freight</h1>
<p>Consignment tracking and depot hours.</p>
</body></html>
HTML
chmod 644 /var/www/localhost/htdocs/index.html

/usr/sbin/sshd
/usr/sbin/telnetd -l /bin/login
lighttpd -f /etc/lighttpd/lighttpd.conf

# --- back to no filtering and no detection ---------------------------------
iptables -F
iptables -X 2>/dev/null || true
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Suricata is stopped and waited for, not just signalled. It flushes its logs
# and closes its capture before it exits, which takes a second or two, and a
# reset that returned while it was still running would leave the next start
# fighting the previous one for the same netfilter queue.
pkill -x suricata 2>/dev/null || true
i=0
while pgrep -x suricata >/dev/null 2>&1 && [ "$i" -lt 40 ]; do
    i=$(( i + 1 ))
    sleep 0.25
done
pkill -KILL -x suricata 2>/dev/null || true

rm -f /etc/suricata/rules/local.rules
cp /usr/local/share/minilabs/suricata.yaml.orig /etc/suricata/suricata.yaml
mkdir -p /var/log/suricata
chmod 755 /var/log/suricata
rm -f /var/log/suricata/fast.log /var/log/suricata/eve.json \
      /var/log/suricata/stats.log /var/log/suricata/suricata.log \
      /var/log/suricata/stdout.log

echo "[server] 124.0.0.10/24 via 124.0.0.1; ssh, telnet and http listening; no filter rules, no Suricata"
