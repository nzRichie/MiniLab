#!/usr/bin/env bash
# Print the lab's state and its own success oracle, so the learner reads what
# each stage of Part 2 changed without shelling into three containers.
#
# The oracle is two facts held at once. Least privilege means the credential
# table's contents no longer leave the database AND the search page still returns
# the published catalogue. Either one alone is easy: an account with no grants at
# all stops every technique and also stops the shop, and the starter grants keep
# the shop working and hand an attacker the account table.
#
# It reads state and it does not grade anything the learner is marked on. Its
# probes do send payloads through both endpoints: that is the only way to report
# what an injection can currently reach, which is the question the whole of Part 2
# answers. Every probe is a SELECT, so running Status repeatedly changes nothing.
#
# Every probe comes from lib.sh, so what this prints and what selftest.sh asserts
# cannot drift apart.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

hr()  { printf '%s\n' "------------------------------------------------------------"; }
sec() { echo; hr; echo "$*"; hr; }
mark() { if [ "$1" = yes ]; then printf '  [done] '; else printf '  [    ] '; fi; }

if ! running "$DB_CTN"; then
    echo "The lab is not running ($DB_CTN is not up)."
    echo "Start it with the Spawn action, or scripts/spawn.sh."
    exit 1
fi

sec "Containers"
for ctn in "$WEB_CTN" "$DB_CTN" "$ATTACKER_CTN" "$SW_CTN"; do
    if running "$ctn"; then printf '  %-28s up\n' "$ctn"
    else                    printf '  %-28s DOWN\n' "$ctn"; fi
done

if ! db_running; then
    echo
    echo "  MariaDB is not answering on $DB_CTN, so both endpoints print their"
    echo "  failure text whatever you send them. Run the Reset action."
fi
if ! lighttpd_running; then
    echo
    echo "  lighttpd is not running on $WEB_CTN, so neither endpoint answers."
    echo "  Run the Reset action to put the storefront back to its starter state."
fi

# ---------------------------------------------------------------------------
sec "What the application account may do"
grants="$( app_grants )"
if [ -z "$grants" ]; then
    echo "  could not read SHOW GRANTS FOR '${APP_USER}'@'%'"
else
    echo "$grants" | sed 's/^/  /'
fi

# ---------------------------------------------------------------------------
sec "Who may open a connection to the database's port"
rules="$( nft_ruleset )"
if [ -z "$rules" ]; then
    echo "  no filter. Every host on ${SUBNET} may open a connection to"
    echo "  ${DB_IP}:${DB_PORT}, whatever account it means to use."
else
    echo "$rules" | sed 's/^/  /'
fi

# ---------------------------------------------------------------------------
sec "What an injection reaches right now"
echo "  Four payloads, sent now from ${ATTACKER_IP} through the two endpoints:"
echo

taut="$( technique_tautology )"
uni="$( technique_union )"
blind="$( technique_blind )"
lf="$( technique_loadfile )"

if [ "$taut" -gt "$PUBLISHED_COUNT" ]; then
    printf '    %-52s %s\n' "1  tautology: product rows returned" \
        "$taut (${PUBLISHED_COUNT} published, $(( taut - PUBLISHED_COUNT )) hidden)"
else
    printf '    %-52s %s\n' "1  tautology: product rows returned" "$taut (no hidden rows)"
fi
printf '    %-52s %s\n' "2  UNION into ${DB_NAME}.credential returns the rows" "$uni"
printf '    %-52s %s\n' "3  blind extraction through the stock endpoint" "$blind"
printf '    %-52s %s\n' "4  LOAD_FILE returns ${BACKUP_CNF}" "$lf"
echo
printf '    %-52s %s\n' "the account still holds FILE on *.*" "$( app_has_file_privilege )"

# ---------------------------------------------------------------------------
sec "Does the recovered password still open a direct connection?"
echo "  One login attempt as '${BACKUP_USER}' from ${ATTACKER_IP} to ${DB_IP}:${DB_PORT},"
echo "  with no web request involved."
echo
direct="$( direct_login )"
printf '    %-52s %s\n' "the login succeeds and reads ${DB_NAME}.credential" "$direct"

# ---------------------------------------------------------------------------
sec "Does the shop still work?"
rows="$( published_rows )"
serves="$( page_serves )"
if [ "$serves" = ok ]; then
    printf '    an ordinary search returns %s published products              OK\n' "$rows"
else
    printf '    an ordinary search returns %s products, expected %s          FAIL\n' "$rows" "$PUBLISHED_COUNT"
fi

# ---------------------------------------------------------------------------
sec "Where the lab stands"

working=0
[ "$taut" -gt "$PUBLISHED_COUNT" ] && working=$(( working + 1 ))
[ "$uni"   = yes    ] && working=$(( working + 1 ))
[ "$blind" = usable ] && working=$(( working + 1 ))
[ "$lf"    = yes    ] && working=$(( working + 1 ))
printf '  %s of the 4 techniques return their expected data.\n\n' "$working"

held=no
[ "$uni" = no ] && [ "$blind" = blocked ] && [ "$direct" = no ] && held=yes
mark "$held"; echo "the account table stays in the database: no UNION, no blind channel,"
echo "         and no direct login reads it"

works=no
[ "$serves" = ok ] && works=yes
mark "$works"; echo "the shop still works: an ordinary search returns its ${PUBLISHED_COUNT} published products"

both=no
[ "$held" = yes ] && [ "$works" = yes ] && both=yes
mark "$both"; echo "least privilege holds: both facts at once"

echo
echo "  Technique 1 is not on that list, and its absence is the lesson rather"
echo "  than an omission. The unreleased products live in the one table the shop"
echo "  legitimately reads, so an account narrow enough to stop a tautology"
echo "  reaching them is an account too narrow to run the search. Ending"
echo "  technique 1 takes a change to the statement, not to the grants."
