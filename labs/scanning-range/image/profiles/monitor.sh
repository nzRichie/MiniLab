#!/bin/sh
# The monitoring agent profile: a line protocol of its own, on a drawn high port.
#
# Nothing in nmap's service database matches it, and that is the point. A scanner
# reports the port as open and names it from the port-number list, which for a
# port in this range means it names it wrongly or not at all; the only way to
# find out what is behind it is to connect and read what it says.
#
# What it says is a greeting naming the product and its release, and it answers
# three commands. That is what a small vendor's agent does, and identifying it is
# a banner grab and a guess at a verb, not a scanner flag.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the monitor profile"
VERSION="$( param monitor_version )"
[ -n "$VERSION" ] || VERSION="2.4"

cat > /usr/local/bin/lab-monitor <<RESPONDER
#!/bin/sh
printf 'NODEWATCH %s ready\r\n' '$VERSION'
while IFS= read -r line; do
    line="\$( printf '%s' "\$line" | tr -d '\r' | tr 'a-z' 'A-Z' )"
    case "\$line" in
        ID*)     printf 'NODEWATCH %s agent on %s\r\n' '$VERSION' "\$( hostname )" ;;
        STAT*)   printf 'OK uptime=%s load=0.04\r\n' "\$( cut -d. -f1 /proc/uptime )" ;;
        HELP*)   printf 'COMMANDS: ID STAT HELP QUIT\r\n' ;;
        QUIT*)   printf 'BYE\r\n'; exit 0 ;;
        '')      ;;
        *)       printf 'ERR unknown command\r\n' ;;
    esac
done
RESPONDER
chmod 755 /usr/local/bin/lab-monitor

pkill -f "TCP4-LISTEN:${port}" 2>/dev/null
socat -T60 "TCP4-LISTEN:${port},reuseaddr,fork" EXEC:/usr/local/bin/lab-monitor >/dev/null 2>&1 &
wait_listening tcp "$port" || die "the monitoring agent is not listening on $port"

describe tcp "$port" nodewatch "$VERSION" nodewatch monitor monitoring agent

echo "profile monitor: up"
