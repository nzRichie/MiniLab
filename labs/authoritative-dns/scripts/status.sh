#!/usr/bin/env bash
# Print the lab's state and its success oracle, so the learner reads what each
# server holds without shelling into any of them.
#
# The oracle is four questions, one per part of the handout:
#
#   1  does the primary answer authoritatively for every record in the forward zone
#   2  does the secondary hold the same zone, at the same serial, and does it
#      refuse a transfer to anybody the primary did not name
#   3  does the primary REFER the child zone downwards, with the address of the
#      server it refers to, and does the client reach a name inside it from the root
#   4  does dig -x return a name for each address in the lab's /24
#
# Nothing here changes any state. Every query is sent from the client container
# with recursion switched off, except the handful that deliberately go through
# the resolver, which are marked as such.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

pass=0
fail=0

hr() { printf '%s\n' "-------------------------------------------------------------------------"; }

# One check, printed as a fixed-width line so a column of them reads down the
# page. The detail is what was actually seen, which is the part a learner needs
# when the answer is no.
check() {   # <ok|no> <label> [detail]
    if [ "$1" = ok ]; then
        pass=$(( pass + 1 ))
        printf '  [ ok ] %-46s %s\n' "$2" "${3:-}"
    else
        fail=$(( fail + 1 ))
        printf '  [FAIL] %-46s %s\n' "$2" "${3:-}"
    fi
}

running() {   # <container>
    docker ps --format '{{.Names}}' | grep -qx "$1"
}

docker ps --format '{{.Names}}' | grep -qx "$PRIMARY_CTN" || {
    echo "The lab is not running ($PRIMARY_CTN is not up). Spawn it first." >&2
    exit 1
}

echo
echo "Authoritative DNS, zone authoring and delegation -- status"
hr

# --- the machines ---------------------------------------------------------
echo "Machines"
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    if ! running "$ctn"; then
        check no "$ctn" "not running"
    elif named_running "$ctn"; then
        check ok "$ctn" "named running"
    else
        check no "$ctn" "container up, named NOT running"
    fi
done
echo

# --- part 1: the forward zone --------------------------------------------
echo "Part 1  the forward zone on $NS1_NAME ($PRIMARY_IP)"
if zone_is_loaded "$PRIMARY_CTN" "$ZONE"; then
    serial="$( soa_serial "$PRIMARY_IP" "$ZONE" )"
    check ok "$ZONE is loaded" "serial ${serial:-unknown}"
else
    check no "$ZONE is loaded" "named holds no such zone"
fi

while read -r server name type want; do
    [ -n "$name" ] || continue
    if check_record "$server" "$name" "$type" $want; then
        check ok "$name $type" "$want"
    else
        check no "$name $type" "wanted '$want', got '$( actual_record "$server" "$name" "$type" )'"
    fi
done <<< "$( forward_records )"

# A name that is in no zone. The interesting part is not that it fails but how:
# a server authoritative for uni.lab answers NXDOMAIN with the aa bit set and
# puts the zone's SOA in the authority section, which is the record that tells a
# resolver how long to remember the absence.
absent="$( dig_direct "$PRIMARY_IP" "$ABSENT_NAME" A )"
if [ "$( dig_status "$absent" )" = "NXDOMAIN" ] && dig_flags "$absent" | grep -qw aa; then
    check ok "$ABSENT_NAME is denied authoritatively" \
             "NXDOMAIN, SOA TTL $( dig_ttl "$absent" AUTHORITY SOA )"
else
    check no "$ABSENT_NAME is denied authoritatively" \
             "got $( dig_status "$absent" ), flags '$( dig_flags "$absent" )'"
fi
echo

# --- part 2: the secondary and the transfer -------------------------------
echo "Part 2  the copy on $NS2_NAME ($SECONDARY_IP)"
if zone_is_loaded "$SECONDARY_CTN" "$ZONE"; then
    check ok "$ZONE is loaded on the secondary" \
             "serial $( soa_serial "$SECONDARY_IP" "$ZONE" )"
else
    check no "$ZONE is loaded on the secondary" "named holds no such zone"
fi

p_serial="$( soa_serial "$PRIMARY_IP" "$ZONE" )"
s_serial="$( soa_serial "$SECONDARY_IP" "$ZONE" )"
if [ -n "$p_serial" ] && [ "$p_serial" = "$s_serial" ]; then
    check ok "the two copies are at the same serial" "$p_serial"
else
    check no "the two copies are at the same serial" \
             "primary '${p_serial:-none}', secondary '${s_serial:-none}'"
fi

# Every record the primary serves, served by the secondary too, and served
# authoritatively: a secondary answers out of its own copy of the zone, not by
# asking the primary.
sec_missing=0
while read -r server name type want; do
    [ -n "$name" ] || continue
    check_record "$server" "$name" "$type" $want || sec_missing=$(( sec_missing + 1 ))
done <<< "$( secondary_records )"
total_records="$( forward_records | grep -c . )"
if [ "$sec_missing" -eq 0 ]; then
    check ok "the secondary replies for every record" "$total_records of $total_records"
else
    check no "the secondary replies for every record" \
             "$(( total_records - sec_missing )) of $total_records"
fi

# Who may take a copy. The primary is the one that decides; the secondary's own
# transfer policy is not what this checks.
if axfr_refused "$PRIMARY_IP" "$ZONE"; then
    check ok "a transfer to the client is refused by the primary" "Transfer failed"
else
    n="$( axfr_records "$PRIMARY_IP" "$ZONE" )"
    check no "a transfer to the client is refused by the primary" \
             "the primary handed over $n record(s)"
fi
echo

# --- part 3: the delegation ----------------------------------------------
echo "Part 3  the delegation of $CHILD_ZONE ($SUB_IP)"
ref="$( dig_direct "$PRIMARY_IP" "$CHILD_WWW_NAME" A )"
if is_referral "$PRIMARY_IP" "$CHILD_WWW_NAME" A; then
    check ok "the parent refers $CHILD_WWW_NAME downwards" \
             "ANSWER 0, AUTHORITY $( dig_count "$ref" AUTHORITY ), ADDITIONAL $( dig_count "$ref" ADDITIONAL ), flags '$( dig_flags "$ref" )'"
else
    check no "the parent refers $CHILD_WWW_NAME downwards" \
             "status $( dig_status "$ref" ), ANSWER $( dig_count "$ref" ANSWER ), flags '$( dig_flags "$ref" )'"
fi

# The glue. The referral names ns1.cs.uni.lab, which is inside the zone being
# referred to, so the parent has to carry its address or the referral is a
# pointer nothing can follow.
if printf '%s\n' "$ref" | awk '/^;; ADDITIONAL SECTION:/{a=1;next} /^;;/{a=0} a' \
        | grep -q "$SUB_IP"; then
    check ok "the referral carries the address of $CHILD_NS_NAME" "$SUB_IP in ADDITIONAL"
else
    check no "the referral carries the address of $CHILD_NS_NAME" \
             "no glue address in the additional section"
fi

if zone_is_loaded "$SUB_CTN" "$CHILD_ZONE"; then
    check ok "$CHILD_ZONE is loaded on its own server" \
             "serial $( soa_serial "$SUB_IP" "$CHILD_ZONE" )"
else
    check no "$CHILD_ZONE is loaded on its own server" "named holds no such zone"
fi

while read -r server name type want; do
    [ -n "$name" ] || continue
    if check_record "$server" "$name" "$type" $want; then
        check ok "$name $type" "$want"
    else
        check no "$name $type" "wanted '$want', got '$( actual_record "$server" "$name" "$type" )'"
    fi
done <<< "$( child_records )"

# Through the resolver, which was told nothing but where the root is. This is
# the one check that exercises the whole chain rather than one server.
got="$( resolves_to "$CHILD_WWW_NAME" A )"
if [ "$got" = "$SUB_IP" ]; then
    check ok "the resolver reaches $CHILD_WWW_NAME from the root" "$got"
else
    check no "the resolver reaches $CHILD_WWW_NAME from the root" "got '${got:-nothing}'"
fi
echo

# --- part 4: the reverse zone --------------------------------------------
echo "Part 4  the reverse zone $REVERSE_ZONE ($PRIMARY_IP)"
if zone_is_loaded "$PRIMARY_CTN" "$REVERSE_ZONE"; then
    check ok "$REVERSE_ZONE is loaded" "serial $( soa_serial "$PRIMARY_IP" "$REVERSE_ZONE" )"
else
    check no "$REVERSE_ZONE is loaded" "named holds no such zone"
fi

while read -r server name type want; do
    [ -n "$name" ] || continue
    if check_record "$server" "$name" "$type" $want; then
        check ok "$name $type" "$want"
    else
        check no "$name $type" "wanted '$want', got '$( actual_record "$server" "$name" "$type" )'"
    fi
done <<< "$( reverse_records )"
echo

# --- the whole chain, end to end -----------------------------------------
echo "End to end, through the resolver at $CLIENT_IP"
for pair in "$WWW_NAME $PARENT_WEB_MARKER" "$CHILD_WWW_NAME $CHILD_WEB_MARKER"; do
    set -- $pair
    body="$( fetch "http://$1/" )"
    if printf '%s' "$body" | grep -q "$2"; then
        check ok "http://$1/ reaches the right machine" "$2"
    else
        check no "http://$1/ reaches the right machine" "got '${body:-no response}'"
    fi
done

if pings6 "$PRIMARY_IP6"; then
    check ok "the address in the AAAA record replies to an echo request" "$PRIMARY_IP6"
else
    check no "the address in the AAAA record replies to an echo request" "$PRIMARY_IP6 silent"
fi
echo

hr
if [ "$fail" -eq 0 ]; then
    echo "  $pass check(s) passed. Every zone in the lab is complete."
else
    echo "  $pass passed, $fail still to do."
fi
hr
echo

# A failing check is not always a zone that is missing a record: a zone file
# named refuses to load leaves the whole zone absent, and the reason is only in
# the log. Printing the tail of each learner-configured server's log here saves a
# shell session per server.
if [ "$fail" -gt 0 ]; then
    echo "The last few lines of each server's log:"
    for d in "${LEARNER_DEVICES[@]}"; do
        ctn="$( ctn_of "$d" )"
        echo
        echo "  $ctn"
        named_log_tail "$ctn" 6 | sed 's/^/    /'
    done
    echo
fi

exit 0
