#!/bin/sh
# The print server profile: a PJL listener on tcp/9100.
#
# Port 9100 is raw printing. There is no protocol negotiation and no
# authentication: whatever is written to the socket is printed, and a printer
# that speaks HP's Printer Job Language answers a small set of queries about
# itself on the same socket. `@PJL INFO ID` returns the model and the firmware
# release, which is a version obtained by asking the device a question rather
# than by reading a greeting it volunteered.
#
# It is socat in front of a shell script because no Alpine package is a printer.
# What it answers is what a real device answers to the same three queries, and
# nothing about it pretends to be a general-purpose service.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the jetdirect profile"
MODEL="$( param printer_model )"
[ -n "$MODEL" ] || MODEL="LaserJet 4250"
FIRMWARE="$( param printer_firmware )"
[ -n "$FIRMWARE" ] || FIRMWARE="20230412 08.180.4"

cat > /usr/local/bin/lab-pjl <<RESPONDER
#!/bin/sh
# One raw-print session. Anything that is not a PJL command is print data, which
# a printer accepts silently, which is why the default case says nothing.
while IFS= read -r line; do
    line="\$( printf '%s' "\$line" | tr -d '\r' )"
    case "\$line" in
        *'@PJL INFO ID'*)
            printf '@PJL INFO ID\r\n"%s"\r\n\014' '$MODEL'
            ;;
        *'@PJL INFO CONFIG'*)
            printf '@PJL INFO CONFIG\r\nIN TRAYS [2 ENUMERATED]\r\n\014'
            ;;
        *'@PJL INFO STATUS'*)
            printf '@PJL INFO STATUS\r\nCODE=10001\r\nDISPLAY="Ready"\r\nONLINE=TRUE\r\n\014'
            ;;
        *'@PJL INFO VARIABLES'*|*'@PJL INFO PRODINFO'*)
            printf '@PJL INFO VARIABLES\r\nFIRMWARE=%s\r\n\014' '$FIRMWARE'
            ;;
        *'@PJL'*)
            printf '@PJL\r\n\014'
            ;;
    esac
done
RESPONDER
chmod 755 /usr/local/bin/lab-pjl

pkill -f "TCP4-LISTEN:${port}" 2>/dev/null
socat -T60 "TCP4-LISTEN:${port},reuseaddr,fork" EXEC:/usr/local/bin/lab-pjl >/dev/null 2>&1 &
wait_listening tcp "$port" || die "the print service is not listening on $port"

# The firmware release is what the device gives up, and it gives it up only when
# asked. It is recorded here in the same form the query returns it, which is the
# form a learner reads off their own terminal.
describe tcp "$port" jetdirect "$( version_digits "$FIRMWARE" )" \
    jetdirect pdl-datastream printer pjl hp-pjl

echo "profile jetdirect: up"
