#!/bin/sh
# The SNMP agent profile: net-snmp on udp/161, answering the community string it
# shipped with.
#
# It is the range's second route to the map. `snmpwalk` against it returns the
# machine's own interface table and address table, and on a router-adjacent
# machine that names subnets a sweep has not reached yet. It is also the one
# place a machine says its class out loud: sysDescr is set to what this equipment
# is, and sysContact names the team, which on some ranges is where the shared
# account's name comes from.
#
# The community is `public`, which is the string net-snmp's own documentation
# uses in every example and which a great deal of equipment still ships with. No
# credential is being broken here: the service is answering the question it was
# configured to answer, to anybody who asks it.
#
# The ghost interface, where the seed drew one, is a real interface on this
# machine: administratively down, holding an address in a block that is routed
# nowhere. It appears in the address table exactly as a live one does. A learner
# who reports that block as a segment without probing it pays the subnet penalty,
# which is the whole reason it is here.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_udp )"
[ -n "$port" ] || die "no udp port drawn for the snmp profile"
ACCOUNT="$( param leak_account )"
SITE="$( org_site 1 )"

conf=/etc/snmp/lab.conf
{
    echo "rocommunity public default"
    printf 'sysDescr %s - %s\n' "${CLASS_SYSDESCR:-Linux host}" "$ORG_NAME"
    printf 'sysName %s\n' "$( hostname )"
    if [ -n "$ACCOUNT" ]; then
        printf 'sysContact %s <%s@%s>\n' "$ORG_TEAM" "$ACCOUNT" "$ORG_ZONE"
    else
        printf 'sysContact %s\n' "$ORG_TEAM"
    fi
    printf 'sysLocation %s\n' "$SITE"
} > "$conf"

# -C is load-bearing. Without it net-snmp reads the packaged /etc/snmp/snmpd.conf
# IN ADDITION to the one named with -c, that file carries an agentaddress of its
# own, and the agent tries to bind udp/161 twice and dies with "Error opening
# specified endpoint" and nothing about a duplicate.
pkill -x snmpd 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x snmpd >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
snmpd -C -c "$conf" -Lf /var/log/snmpd.log "udp:${port}" \
    || die "snmpd failed to start on udp/$port"
wait_listening udp "$port" || die "snmpd is not listening on udp/$port"

# No version is recorded, and that is the truth about this service rather than a
# gap in the range. sysDescr is a description of the equipment, which is what the
# operator wrote in it; the agent's own release is not on the wire at all, and
# nmap's version detection reports the community it guessed rather than a number.
describe udp "$port" snmp "" snmp snmpd net-snmp

intel snmp-public
[ -n "$( param ghost_net )" ] && intel snmp-map
echo "profile snmp: up"
