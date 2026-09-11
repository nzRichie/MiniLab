#!/bin/sh
# The scanner's upload endpoint.
#
# It reads the POSTed file, scans it with clamscan against the database the
# learner deployed at /etc/minilabs/deployed.yar, and answers ACCEPTED or
# REJECTED. Everything clamscan writes to standard error is copied into the
# reply, because the loader's complaints are the point of the first half of
# Part 4: a database clamscan could not parse leaves it scanning with no
# signatures at all, and it reports that file clean.
#
# The body is read raw rather than as a multipart form, so the client posts a
# file with `curl --data-binary @FILE` and nothing here has to parse a
# boundary.
set -u

DB=/etc/minilabs/deployed.yar
SPOOL=/var/spool/uploads

name=$(printf '%s' "${QUERY_STRING:-}" | sed -n 's/^.*name=\([A-Za-z0-9._-]\{1,64\}\).*$/\1/p')
[ -n "$name" ] || name=upload.bin

printf 'Content-Type: text/plain\r\n\r\n'

if [ "${REQUEST_METHOD:-GET}" != POST ]; then
    echo "usage: POST the file body to /cgi-bin/upload.cgi?name=FILENAME"
    exit 0
fi

mkdir -p "$SPOOL"
chmod 755 "$SPOOL"
target="${SPOOL}/${name}"
head -c "${CONTENT_LENGTH:-0}" > "$target"
chmod 644 "$target"

if [ ! -s "$target" ]; then
    echo "REJECTED ${name}: empty upload"
    rm -f "$target"
    exit 0
fi

if [ ! -s "$DB" ]; then
    echo "SCANNER ERROR: no database at ${DB}"
    rm -f "$target"
    exit 0
fi

out=$(clamscan --no-summary -d "$DB" "$target" 2>&1)
rc=$?

# The loader's own lines, verbatim, before the verdict.
printf '%s\n' "$out" | grep -E '^LibClamAV' || true

sig=$(printf '%s\n' "$out" | sed -n "s|^${target}: \(.*\) FOUND\$|\1|p")

case "$rc" in
    0) echo "ACCEPTED ${name}" ;;
    1) echo "REJECTED ${name}: ${sig:-unnamed signature}" ;;
    *) echo "SCANNER ERROR ${name}: clamscan exit ${rc}" ;;
esac

rm -f "$target"
exit 0
