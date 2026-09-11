#!/usr/bin/env bash
# Print the lab's state and its own success oracle, so the learner reads what
# changed without shelling into anything.
#
# Three blocks, in the order Part 2 closes them:
#
#   Reach     which files the traversal reads from the attacker's machine, in
#             both spellings. This is what stages 2A and 2B move.
#   Reuse     whether the credential the traversal currently discloses opens a
#             database session from the attacker's machine. This is what stages
#             2C and 2D move, and it is the plan's oracle for the whole lab.
#   Service   the portal serving a document, and the nightly report job running.
#             Both must stay green through every stage: a defence that works by
#             taking a tier away fails here.
#
# The credential tested under Reuse is read out of the web host's file THROUGH
# the traversal, so after stage 2D it is whatever account and password the
# learner put there rather than the one the lab shipped.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

for ctn in "$WEB_CTN" "$DB_CTN" "$REPORTS_CTN" "$ATTACKER_CTN" "$SW_CTN"; do
    running "$ctn" || {
        echo "Lab is not fully up: $ctn is not running. Spawn it first." >&2
        exit 1
    }
done

hr() { printf '%s\n' "----------------------------------------------------------------------"; }
row() { printf '  %-38s %s\n' "$1" "$2"; }

echo "Path traversal to credential reuse -- AS ${AS}, ${SUBNET}"
hr
row "portal      ${WEB_IP}" "$( lighttpd_running && echo 'lighttpd is running' || echo 'lighttpd is NOT running' )"
row "database    ${DB_IP}" "$( db_running && echo 'MariaDB is accepting connections' || echo 'MariaDB is NOT accepting connections' )"
row "reports     ${REPORTS_IP}" "runs ${REPORT_CMD}"
row "attacker    ${ATTACKER_IP}" "every request below is sent from here"
echo

echo "Configuration the defence stages change"
hr
row "request filter on the query string" "$( request_filter_present )"
ob="$( open_basedir_value )"
row "open_basedir in ${PHP_INI}" "${ob:-not set}"
echo "  database accounts:"
app_accounts | sed 's/^/    /'
echo

echo "Reach: what the traversal reads, from ${ATTACKER_IP}"
hr
row "a document the portal serves" "$( [ "$( page_serves )" = ok ] && echo 'read' || echo 'NOT read' )"
row "/etc/passwd  spelled ../" "$( passwd_literal )"
row "/etc/passwd  spelled %2e%2e%2f" "$( passwd_encoded )"
row "${LIGHTTPD_CONF}" "$( lighttpd_conf_readable )"
row "${VIEW_FILE}  (source, not run)" "$( view_source_readable )"
row "${DB_INC}" "$( db_inc_readable )"
echo

echo "Reuse: the disclosed credential, used from ${ATTACKER_IP}"
hr
cred="$( disclosed_credential )" || true
if [ -n "$cred" ]; then
    row "account the traversal discloses" "${cred%% *}"
else
    row "account the traversal discloses" "none disclosed"
fi
reuse="$( credential_reuse )"
case "$reuse" in
    accepted) row "database session from the attacker" "ACCEPTED -- the customer table is readable" ;;
    refused)  row "database session from the attacker" "refused -- $( reuse_error )" ;;
    none)     row "database session from the attacker" "not attempted: no credential was disclosed" ;;
esac
echo

echo "Service: both tiers still work"
hr
row "portal serves ${DOC_A}" "$( page_serves )"
row "nightly report job on ${REPORTS_IP}" "$( report_job )"
echo
hr
echo "Done when: the database session is refused, and both service lines read ok."
