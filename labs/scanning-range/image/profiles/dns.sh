#!/bin/sh
# The authoritative DNS profile: BIND, on port 53, at normal and above.
#
# It is authoritative for one zone and it allows a transfer of that zone to
# anybody who asks. The zone names every live segment's gateway and every host in
# the range, so `dig AXFR` against this host hands over the map in one command.
#
# That shortcut is deliberate and it is what the zone-transfer intel item pays
# for. A server that will hand its whole zone to an unauthenticated client is a
# real and common finding, and a learner who thinks to try it has done the thing
# the range is drilling. It gives up the map only: the zone names addresses, not
# what is listening on them, so the survey half of the range is untouched by it.
set -u
. /etc/minilabs/profiles/_lib.sh

ZONE="$( param zone )"
[ -n "$ZONE" ] || ZONE="$ORG_ZONE"
[ -n "$ZONE" ] || die "no zone drawn for the dns profile"
[ -f /etc/minilabs/zone.data ] || die "spawn wrote no zone data"

mkdir -p /var/bind /var/run/named
chmod 755 /var/bind /var/run/named

# The zone body is built from the name/address pairs spawn.sh wrote out of
# state/topology.env, so the zone cannot disagree with the network it describes.
{
    cat <<HEAD
\$TTL 3600
@       IN  SOA ns.${ZONE}. hostmaster.${ZONE}. (
                2026083101  ; serial
                3600        ; refresh
                600         ; retry
                1209600     ; expire
                3600 )      ; negative caching TTL
@       IN  NS  ns.${ZONE}.
HEAD
    while IFS='	' read -r name ip; do
        [ -n "$name" ] || continue
        printf '%-16s IN  A   %s\n' "$name" "$ip"
    done < /etc/minilabs/zone.data
} > "/var/bind/${ZONE}.zone"

# The reverse zones, one per /24 the forward zone names, and the reason they
# exist is that a learner has to be able to LEARN the zone name. The organisation
# is drawn per spawn, so the manual cannot print it, and an authoritative server
# with recursion off answers nothing about a name it does not hold. A PTR lookup
# on any address in the range returns a name, and the name carries the zone,
# which is what makes `dig AXFR` a command a learner can arrive at rather than
# guess. An internal name server that holds the forward zone almost always holds
# the reverse one too, so nothing here is arranged for the exercise's benefit.
REV_NETS=""
while IFS='	' read -r name ip; do
    [ -n "$ip" ] || continue
    n="$( echo "$ip" | cut -d. -f1-3 )"
    case " $REV_NETS " in *" $n "*) ;; *) REV_NETS="${REV_NETS:+$REV_NETS }$n" ;; esac
done < /etc/minilabs/zone.data

for n in $REV_NETS; do
    a="$( echo "$n" | cut -d. -f1 )"; b="$( echo "$n" | cut -d. -f2 )"; c="$( echo "$n" | cut -d. -f3 )"
    revzone="${c}.${b}.${a}.in-addr.arpa"
    {
        cat <<HEAD
\$TTL 3600
@       IN  SOA ns.${ZONE}. hostmaster.${ZONE}. (
                2026090101  ; serial
                3600        ; refresh
                600         ; retry
                1209600     ; expire
                3600 )      ; negative caching TTL
@       IN  NS  ns.${ZONE}.
HEAD
        while IFS='	' read -r name ip; do
            [ -n "$ip" ] || continue
            [ "$( echo "$ip" | cut -d. -f1-3 )" = "$n" ] || continue
            printf '%-4s IN  PTR %s.%s.\n' "$( echo "$ip" | cut -d. -f4 )" "$name" "$ZONE"
        done < /etc/minilabs/zone.data
    } > "/var/bind/${revzone}.zone"
done

cat > /etc/bind/named.conf <<CONF
options {
    directory "/var/bind";
    pid-file "/var/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    // Authoritative only: it answers for the one zone it holds and refuses
    // everything else, which is what an organisation's own name server does.
    recursion no;
    // Nothing here is signed, so there is nothing to validate and no trust
    // anchor to load. Saying so stops named priming itself against root servers
    // this network does not have.
    dnssec-validation no;
};

zone "${ZONE}" {
    type primary;
    file "/var/bind/${ZONE}.zone";
    // The whole point of this host on the range: any client may take a copy of
    // the entire zone, with no key and no address restriction.
    allow-transfer { any; };
};
CONF

for n in $REV_NETS; do
    a="$( echo "$n" | cut -d. -f1 )"; b="$( echo "$n" | cut -d. -f2 )"; c="$( echo "$n" | cut -d. -f3 )"
    revzone="${c}.${b}.${a}.in-addr.arpa"
    cat >> /etc/bind/named.conf <<CONF

zone "${revzone}" {
    type primary;
    file "/var/bind/${revzone}.zone";
    allow-transfer { any; };
};
CONF
done

pkill -x named 2>/dev/null
i=25; while [ $i -gt 0 ] && pgrep -x named >/dev/null 2>&1; do i=$(( i - 1 )); sleep 0.2; done
named -c /etc/bind/named.conf || die "named failed to start"
wait_listening udp 53 || die "named is not listening on udp/53"
wait_listening tcp 53 || die "named is not listening on tcp/53"

# BIND answers a CHAOS-class TXT query for version.bind with its own release, and
# that is the string nmap's version detection reports. Reading it back from the
# server keeps the recorded version and the one on the wire the same.
ver="$( dig @127.0.0.1 -c CH -t TXT version.bind +short 2>/dev/null | tr -d '"' )"
describe udp 53 domain "$( version_digits "$ver" )" domain dns bind named
describe tcp 53 domain "$( version_digits "$ver" )" domain dns bind named

intel zone-transfer
echo "profile dns: authoritative for ${ZONE}"
