#!/usr/bin/env bash
# Print the `docker exec -it` line for every node in the lab, or open a shell on
# one of them.
#
# The lab is worked from three machines: the c2, where every flood is started;
# the admin, where every measurement is taken; and the router, where both
# shapers and every filter live. The victim is the fourth, for reading its
# connection state and its name server's log.
#
# The TUI streams output non-interactively and cannot host a PTY, so with no
# terminal attached this prints one line per node and the learner pastes the one
# they want. Given a node name as $1 from a real terminal it opens that shell.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

ROLES="router server admin host1 host2 host3 host4 host5 host6 c2 loader"

running="$( docker ps --format '{{.Names}}' 2>/dev/null )"
state_of() { grep -qxF "$1" <<< "$running" || echo "   (not running)"; }

ctn_width=0
for role in $ROLES; do
    ctn="$( ctn_of "$role" )"
    [ ${#ctn} -gt "$ctn_width" ] && ctn_width=${#ctn}
done

if [ $# -ge 1 ]; then
    role="$1"
    case " $ROLES " in
        *" $role "*) ;;
        *) echo "unknown node '$role'; expected one of: $ROLES" >&2; exit 1 ;;
    esac
    ctn="$( ctn_of "$role" )"
    if [ -t 0 ] && [ -t 1 ]; then exec docker exec -it "$ctn" bash; fi
    echo "Open a terminal and run:"
    echo "    docker exec -it $ctn bash"
    exit 0
fi

node() {   # <role> <description line>...
    local role="$1"; shift
    local ctn; ctn="$( ctn_of "$role" )"
    printf '  %-7s %s\n' "$role" "$1"; shift
    local extra
    for extra in "$@"; do printf '  %-7s %s\n' "" "$extra"; done
    printf '  %-7s docker exec -it %-*s bash%s\n\n' \
        "" "$ctn_width" "$ctn" "$( state_of "$ctn" )"
}

echo "Open a terminal and run the line for the node you want."
echo
node c2     "the console ($C2_IP). Every flood is started from here, over ssh" \
            "to the four sources. One of the three machines you need"
node admin  "the measurement ($ADMIN_IP). Run 'probe --target $SERVER_IP" \
            "--name $VALID_NAME all' here after every change"
node router "the router ($R_INSIDE_IP inside, $R_FIELD_IP field, $R_OP_IP operator)." \
            "Both shapers, every filter and every source check live here"
node server "the victim ($SERVER_IP): web on tcp/80, iperf3 on tcp/5201," \
            "BIND authoritative for ${ZONE_NAME}. on udp/53"
node host1  "flood source ($HOST1_IP)"
node host2  "flood source ($HOST2_IP)"
node host3  "flood source ($HOST3_IP)"
node host4  "flood source ($HOST4_IP)"
node host5  "the DNS reflector ($HOST5_IP): dnsmasq, four TXT record sets"
node host6  "the NTP reflector ($HOST6_IP): ntpsec, mode-6 control queries"
node loader "the file host ($LOADER_IP): serves the flood tool's source text"
