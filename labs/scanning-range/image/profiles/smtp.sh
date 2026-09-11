#!/bin/sh
# The mail service profile: an ESMTP front end on tcp/25, built on socat.
#
# It exists for one command. VRFY asks a mail server whether it knows an address,
# and a server that answers honestly tells an attacker which of a list of guessed
# names is a real account before a single password has been tried. RFC 5321
# section 3.5.3 allows a server to refuse to confirm or deny, and most modern
# servers do; this one is configured the way a great deal of internal mail relay
# still is, which is to answer.
#
# It is socat in front of a shell script rather than a packaged mail server
# because the packaged ones will not answer VRFY at all: OpenSMTPD replies "252
# cannot VRFY user" to every name, existing or not, which is the correct
# behaviour and teaches nothing. A range that wants the enumeration lesson has to
# run a server that enumerates. Nothing else about this service is pretended: it
# accepts no mail, and its greeting says what it is.
set -u
. /etc/minilabs/profiles/_lib.sh

port="$( first_tcp )"
[ -n "$port" ] || die "no tcp port drawn for the smtp profile"
ACCOUNT="$( param smtp_account )"

# The names it will confirm. The real account when the seed put one here, plus a
# handful of ordinary ones so that a VRFY sweep returns a list rather than a
# single hit and the learner has to notice which name is the shared one.
KNOWN="postmaster abuse root ${ACCOUNT}"

cat > /usr/local/bin/lab-smtpd <<RESPONDER
#!/bin/sh
# One SMTP session. socat runs a copy of this per connection.
known="$KNOWN"
printf '220 %s ESMTP %s mail gateway\r\n' "\$( hostname )" '$ORG_NAME'
while IFS= read -r line; do
    line="\$( printf '%s' "\$line" | tr -d '\r' )"
    verb="\$( printf '%s' "\$line" | cut -d' ' -f1 | tr 'a-z' 'A-Z' )"
    arg="\$( printf '%s' "\$line" | cut -s -d' ' -f2- )"
    case "\$verb" in
        HELO) printf '250 %s\r\n' "\$( hostname )" ;;
        EHLO) printf '250-%s\r\n250-VRFY\r\n250 HELP\r\n' "\$( hostname )" ;;
        VRFY)
            user="\${arg%%@*}"
            hit=no
            for k in \$known; do [ "\$user" = "\$k" ] && hit=yes; done
            if [ "\$hit" = yes ]; then
                printf '250 2.1.5 <%s@%s>\r\n' "\$user" '$ORG_ZONE'
            else
                printf '550 5.1.1 <%s>: Recipient address rejected: User unknown\r\n' "\$user"
            fi
            ;;
        MAIL|RCPT|DATA) printf '550 5.7.1 relaying denied\r\n' ;;
        HELP) printf '214 HELO EHLO VRFY QUIT\r\n' ;;
        QUIT) printf '221 2.0.0 Bye\r\n'; exit 0 ;;
        '') ;;
        *) printf '502 5.5.2 Command not recognised\r\n' ;;
    esac
done
RESPONDER
chmod 755 /usr/local/bin/lab-smtpd

pkill -f "TCP4-LISTEN:${port}" 2>/dev/null
socat -T60 "TCP4-LISTEN:${port},reuseaddr,fork" EXEC:/usr/local/bin/lab-smtpd >/dev/null 2>&1 &
wait_listening tcp "$port" || die "the mail service is not listening on $port"

# The greeting names the organisation and not a software release, which is what
# an internal relay behind a hardening standard looks like. No version is on the
# wire, so none is recorded and none is graded.
describe tcp "$port" smtp "" smtp mail esmtp

[ -n "$ACCOUNT" ] && intel smtp-vrfy
echo "profile smtp: up"
