#!/usr/bin/env bash
# Show what the lab is doing, and its success oracle.
#
# The oracle is four things, and each one is answered by a different piece of
# configuration. Whether a message leaves each source machine at all is the
# forwarding rule. Whether the collector accepts it is the input. Whether it
# lands in a file of its own is the ruleset binding and the dynamic file name.
# Whether it lands there with a facility and a severity beside it is the
# template. Each of those fails with the others working, and each of them fails
# with the summary line looking identical, which is why the sections above the
# oracle exist.
#
# The probes are real messages, sent with the same `logger` command the handout
# has the learner type, because there is no way to find out whether a forwarding
# rule works other than by giving it something to forward. Each probe carries a
# token used nowhere else, so a line carrying it can only be that probe.
#
# Nothing here configures anything. It reads state, sends the messages a learner
# sends, and prints what came back.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

pass=0; fail=0
mark() {   # <yes|no> <text>
    if [ "$1" = "yes" ]; then pass=$((pass+1)); printf '  [ ok ] %s\n' "$2"
    else                      fail=$((fail+1)); printf '  [    ] %s\n' "$2"; fi
}

echo "== containers =="
docker ps --filter "name=${AS}_L7_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -v netadmin_helper
echo

# ---------------------------------------------------------------------------
echo "== each machine's own log =="
echo "  A machine's own file is the copy that lives on the machine the event"
echo "  happened to, and it is the copy an intruder with root on that machine can"
echo "  delete."
printf '  %-12s %-10s %s\n' MACHINE 'OWN FILE' 'LINES'
for d in "${DEVICES[@]}"; do
    if local_log_exists "$d"; then
        n="$( local_lines "$d" | wc -l | tr -d ' ' )"
        printf '  %-12s %-10s %s\n' "$d" present "$n"
    else
        printf '  %-12s %-10s %s\n' "$d" DELETED "-"
    fi
done
echo

# ---------------------------------------------------------------------------
echo "== the collector =="
if collector_listening; then
    echo "  Listening on TCP ${SYSLOG_PORT}."
else
    echo "  Not listening on TCP ${SYSLOG_PORT}: nothing can reach it, whatever the"
    echo "  three source machines are configured to send."
fi
files="$( remote_dir_listing )"
if [ -n "$files" ]; then
    echo "  Files under ${REMOTE_DIR}:"
    docker exec "$COLLECTOR_CTN" sh -c "ls -la '$REMOTE_DIR'" 2>/dev/null | tail -n +2 | sed 's/^/    /'
else
    echo "  ${REMOTE_DIR} is empty."
fi
echo

echo "  Rotation policy (${LOGROTATE_CONF}):"
if docker exec "$COLLECTOR_CTN" test -f "$LOGROTATE_CONF" 2>/dev/null; then
    docker exec "$COLLECTOR_CTN" cat "$LOGROTATE_CONF" 2>/dev/null | sed 's/^/    /'
    m="$( mode_of collector "$LOGROTATE_CONF" )"
    case "$m" in
        600|644|444|400) echo "    mode ${m}: logrotate will read this file." ;;
        *) echo "    mode ${m}: logrotate REFUSES a configuration file that is group- or" ;
           echo "    world-writable, and skips it with a message about a bad file mode." ;;
    esac
else
    echo "    none."
fi
echo

# ---------------------------------------------------------------------------
# Stage 1. Does anything at all get from each source machine to the collector?
echo "== stage 1: does each machine's message reach the collector =="
declare -A TOKEN=()
# The configuration is checked before the probe, not after it. A machine with no
# forwarding rule, or a collector with nothing bound, will never receive a probe,
# and waiting out the full retry window to establish that makes Status take
# minutes to say what one grep already knows.
for h in "${SOURCES[@]}"; do
    if ! config_has "$h" "$COLLECTOR_IP"; then
        TOKEN[$h]=""
        mark no "$h: no rule on $h names ${COLLECTOR_IP}, so its messages stop on $h"
        continue
    fi
    if ! collector_listening; then
        TOKEN[$h]=""
        mark no "$h: $h is sending, but the collector has nothing bound to TCP ${SYSLOG_PORT}"
        continue
    fi
    if t="$( probe_arrives "$h" perhost 3 )"; then
        TOKEN[$h]="$t"
        mark yes "$h: a message sent on $h arrived at the collector"
    else
        TOKEN[$h]=""
        mark no  "$h: a message sent on $h did not arrive"
        echo "         $h is sending and the collector is listening, so the message arrived"
        echo "         and no rule on the collector wrote it to $( remote_file_of "$h" )."
    fi
done
echo

# ---------------------------------------------------------------------------
# Stage 2. One file per source machine, and none of the collector's own in them.
echo "== stage 2: one file per source machine =="
for h in "${SOURCES[@]}"; do
    f="$( remote_file_of "$h" )"
    if docker exec "$COLLECTOR_CTN" test -f "$f" 2>/dev/null \
    || docker exec "$COLLECTOR_CTN" test -f "$f.1" 2>/dev/null; then
        mark yes "$h: the collector keeps $f"
    else
        mark no  "$h: the collector has no $f"
    fi
done
own="$( remote_file_of collector )"
if docker exec "$COLLECTOR_CTN" test -e "$own" 2>/dev/null; then
    mark no "the collector is filing its OWN messages under $own as well"
    echo   "         Everything reaching this rule is being written, whether it came in"
    echo   "         over the network or from a program on the collector itself."
else
    mark yes "the collector's own messages are not in the per-host files"
fi
echo

# ---------------------------------------------------------------------------
# Stage 3. The fields. A line with no facility and no severity beside it is a
# line an investigator has to read the text of to classify.
echo "== stage 3: the recorded fields =="
for h in "${SOURCES[@]}"; do
    t="${TOKEN[$h]}"
    if [ -z "$t" ]; then
        mark no "$h: no probe arrived, so its recorded fields cannot be read"
        continue
    fi
    line="$( remote_lines_all "$h" | grep -- "$t" | tail -1 )"
    printf '    %s\n' "$line"
    case "$line" in
        *" $h "*) mark yes "$h: the line records the sending machine's hostname" ;;
        *)        mark no  "$h: the line does not record the hostname $h" ;;
    esac
    case "$line" in
        *"${PROBE_FACILITY}.${PROBE_SEVERITY}"*)
            mark yes "$h: it records ${PROBE_FACILITY}.${PROBE_SEVERITY}, which is what the probe asked for" ;;
        *)  mark no  "$h: it does not record ${PROBE_FACILITY}.${PROBE_SEVERITY}" ;;
    esac
done
echo

# ---------------------------------------------------------------------------
# Stage 4. The incident, once it has run.
echo "== stage 4: the incident =="
fails_seen="$( remote_count db "$FAIL_SIGNATURE" )"
accept_seen="$( remote_count db "$ACCEPT_SIGNATURE" )"
lateral_seen="$( remote_count admin "$LATERAL_SIGNATURE" )"
if [ "$fails_seen" -eq 0 ] && [ "$accept_seen" -eq 0 ]; then
    echo "  Not run yet. Finish Parts 2 and 3, then choose the Incident action."
    echo "  It refuses to run, and deletes nothing, until a message sent on db can be"
    echo "  shown to reach the collector."
else
    if local_log_exists db; then
        echo "  db still has its own log file, so the incident has not deleted it yet."
    else
        mark yes "db's own ${LOCAL_LOG} is gone"
    fi
    if [ "$fails_seen" -ge 1 ]; then
        mark yes "the collector still holds ${fails_seen} failed password attempt(s) against ${DB_USER} from ${WEB_IP}"
    else
        mark no  "the collector holds no failed password attempts from ${WEB_IP}"
    fi
    if [ "$accept_seen" -ge 1 ]; then
        mark yes "and the attempt that succeeded"
    else
        mark no  "and no accepted password from ${WEB_IP}"
    fi
    if [ "$lateral_seen" -ge 1 ]; then
        mark yes "admin's file holds the session opened to it from ${DB_IP}"
    else
        mark no  "admin's file holds no session opened from ${DB_IP}"
    fi
fi
echo

# ---------------------------------------------------------------------------
echo "== summary =="
printf '  %d check(s) passing, %d not.\n' "$pass" "$fail"
if [ "$fail" -eq 0 ] && [ "$fails_seen" -ge 1 ]; then
    echo "  Every machine's messages reach the collector, each one has a file of its"
    echo "  own with the sending machine's hostname, facility and severity recorded"
    echo "  beside every line, and what happened to db survives on the collector"
    echo "  after db's own copy was deleted."
elif [ "$fail" -eq 0 ]; then
    echo "  Every machine's messages reach the collector, each one has a file of its"
    echo "  own, and every line carries the sending machine's hostname, facility and"
    echo "  severity. The collector is ready for the incident."
else
    echo "  Stage 1 needs a forwarding rule on the source machine and an input on the"
    echo "  collector. Stage 2 needs the dynamic file name and the ruleset bound to"
    echo "  that input. Stage 3 needs a template that records the fields. Stage 4"
    echo "  needs the Incident action, which will not run until stages 1 to 3 pass."
fi
exit 0
