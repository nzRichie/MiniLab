#!/usr/bin/env bash
# Show what the lab is doing, and its success oracle.
#
# The oracle is the two port sweeps at the bottom: the set of ports the server
# answers on from outside the site, and the set it answers on from the management
# subnet. Those two sets being right, while the public service still answers and
# a password still opens nothing, is what "done" means, and it is the one fact a
# script can read without a human judging a configuration.
#
# The four stages above it exist because a single red sweep says nothing about
# which of forty commands was wrong.
#
# Nothing here configures anything. It reads state and prints it.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

pass=0; fail=0
mark() {   # <ok?> <text>
    if [ "$1" = "yes" ]; then pass=$((pass+1)); printf '  [ ok ] %s\n' "$2"
    else                      fail=$((fail+1)); printf '  [    ] %s\n' "$2"; fi
}

echo "== containers =="
docker ps --filter "name=${AS}_L7_${DC}_" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -v netadmin_helper
echo

echo "== what this lab asks the server to end up with =="
printf '  %-38s %s\n' "reachable from anywhere:"        "tcp/${WEB_PORT} (the public site)"
printf '  %-38s %s\n' "reachable from ${MGMT_SUBNET} only:" "tcp/${SSH_PORT} (SSH)"
printf '  %-38s %s\n' "reachable from nowhere:"          "tcp/${ADMIN_PORT} (the administrative page)"
printf '  %-38s %s\n' "accepted as an SSH credential:"   "a key held by ${ADMIN_CTN}, and nothing else"
echo

# ---------------------------------------------------------------------------
echo "== stage 1: an administrative account that is not root =="
if docker exec "$SERVER_CTN" id -u "$ADMIN_USER" >/dev/null 2>&1; then
    mark yes "account ${ADMIN_USER} exists"
    if docker exec "$SERVER_CTN" id -nG "$ADMIN_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$SUDO_GROUP"; then
        mark yes "${ADMIN_USER} is in the ${SUDO_GROUP} group"
    else
        mark no  "${ADMIN_USER} is not in the ${SUDO_GROUP} group"
    fi
    if docker exec "$SERVER_CTN" grep -qE "^%${SUDO_GROUP}[[:space:]]+ALL=" /etc/sudoers 2>/dev/null; then
        mark yes "/etc/sudoers grants %${SUDO_GROUP}"
    else
        mark no  "/etc/sudoers still has the %${SUDO_GROUP} line commented out"
    fi
    # sshd's StrictModes check ignores an authorized_keys file, or a directory on
    # the path to it, that anyone but its owner can write, and says nothing about
    # it on the client's side: the login simply falls through to the next method.
    # Both are checked because getting one right and the other wrong looks
    # identical from the admin station.
    #
    # What is graded is what sshd enforces, which is ownership plus no write bit
    # for group or other, not the literal mode. The handout has the learner type
    # `chmod 700 ~/.ssh`, and on this image that leaves the directory reading
    # 2700 rather than 700: Alpine's `adduser -D` creates /home/<user> setgid, a
    # directory made underneath it inherits that bit, and busybox `chmod` does
    # not clear it on a directory even when the mode is written as four digits.
    # The setgid bit says which group a new file underneath belongs to and has no
    # bearing on who may write, so a check on the exact digits would fail every
    # learner who did the right thing.
    check_key_mode() {   # <path> <label>
        local out mode owner
        out="$( docker exec "$SERVER_CTN" stat -c '%a %U' "$1" 2>/dev/null )"
        if [ -z "$out" ]; then mark no "$2 does not exist"; return; fi
        mode="${out%% *}"; owner="${out##* }"
        if [ "$owner" != "$ADMIN_USER" ]; then
            mark no "$2 is owned by ${owner}, not ${ADMIN_USER}; sshd will not read it"
        elif [ $(( 0${mode} & 022 )) -ne 0 ]; then
            mark no "$2 is mode ${mode}: writable by group or other, so sshd ignores it"
        else
            mark yes "$2 is mode ${mode}, owned by ${ADMIN_USER}, writable by nobody else"
        fi
    }
    check_key_mode "/home/${ADMIN_USER}/.ssh"                  "~${ADMIN_USER}/.ssh"
    check_key_mode "/home/${ADMIN_USER}/.ssh/authorized_keys"  "~${ADMIN_USER}/.ssh/authorized_keys"
else
    mark no "account ${ADMIN_USER} does not exist yet"
fi
echo

# ---------------------------------------------------------------------------
echo "== stage 2: what sshd_config says, and what the running daemon does =="
# `sshd -T` resolves every include and every compiled-in default and prints the
# effective value, which is what makes it the right thing to read: the file may
# hold a keyword twice, commented, or not at all, and only the first value sshd
# obtains applies.
for kw in PermitRootLogin PasswordAuthentication KbdInteractiveAuthentication; do
    got="$( sshd_config_value "$kw" )"
    if [ "$got" = "no" ]; then
        mark yes "$( printf '%-30s %s' "$kw" "$got" )"
    else
        mark no  "$( printf '%-30s %s   (wanted no)' "$kw" "${got:-unreadable}" )"
    fi
done
echo

# ---------------------------------------------------------------------------
echo "== stage 3: where each service is bound =="
printf '  listening sockets on %s:\n' "$SERVER_CTN"
listeners | sed 's/^/      /'
if listens_on "0.0.0.0" "$WEB_PORT" || listens_on "$SERVER_IP" "$WEB_PORT"; then
    mark yes "the public site is bound where it can be reached (tcp/${WEB_PORT})"
else
    mark no  "nothing is serving the public site on tcp/${WEB_PORT}"
fi
if listens_on "127.0.0.1" "$ADMIN_PORT"; then
    mark yes "the administrative page is bound to 127.0.0.1 only (tcp/${ADMIN_PORT})"
elif listens_on "0.0.0.0" "$ADMIN_PORT"; then
    mark no  "the administrative page is bound to 0.0.0.0: every address the server holds"
else
    mark no  "nothing is serving the administrative page on tcp/${ADMIN_PORT}"
fi
permitopen="$( sshd_config_value PermitOpen )"
if [ "$permitopen" = "127.0.0.1:${ADMIN_PORT}" ]; then
    mark yes "forwarded channels are scoped to 127.0.0.1:${ADMIN_PORT}"
else
    mark no  "PermitOpen is '${permitopen:-any}': a session may forward to anything the server reaches"
fi
echo

# ---------------------------------------------------------------------------
echo "== stage 4: the packet filter =="
if input_policy_is_drop; then
    mark yes "a base chain is registered at the input hook with policy drop"
else
    mark no  "no chain at the input hook has policy drop; nothing is being filtered"
fi
ruleset="$( nft_ruleset )"
if [ -n "$ruleset" ]; then
    printf '%s\n' "$ruleset" | sed 's/^/      /'
else
    echo "      (the ruleset is empty)"
fi
echo

# ---------------------------------------------------------------------------
echo "== stage 5: the oracle, what the server responds to, and to whom =="
echo "  sweeping tcp/${SWEEP_PORTS} on ${SERVER_IP} from two vantages; this takes a few seconds"
echo

# Both sweeps run at once. Against a host that drops, nmap waits out its
# retransmits, and doing that twice in series is twice the wait for a learner
# reading the panel.
tmp="$( mktemp -d )"
trap 'rm -rf "$tmp"' EXIT
sweep "$OUTSIDE_CTN" "$SERVER_IP" > "$tmp/outside" &
sweep "$ADMIN_CTN"   "$SERVER_IP" > "$tmp/admin" &
wait

state_of() {   # <file> <port>
    awk -v p="$2" '$1 == p { print $2; exit }' "$1"
}

printf '  %-8s %-12s %-12s %s\n' "port" "from outside" "from mgmt" "wanted"
for p in $( echo "$SWEEP_PORTS" | tr ',' ' ' ); do
    o="$( state_of "$tmp/outside" "$p" )"
    a="$( state_of "$tmp/admin" "$p" )"
    case "$p" in
        "$WEB_PORT")   want_o=open;    want_a=open;    label="the public site" ;;
        "$SSH_PORT")   want_o=blocked; want_a=open;    label="SSH" ;;
        *)             want_o=blocked; want_a=blocked; label="nothing should respond" ;;
    esac
    printf '  %-8s %-12s %-12s %s\n' "$p" "${o:-?}" "${a:-?}" "$label"
    # "blocked" is anything that is not open. A learner who rejects rather than
    # drops gets `closed` instead of `filtered`, and a learner who moves a
    # service off the address gets `closed` too; both are correct answers to
    # "this port must not answer", and only the reachability is graded here.
    if [ "$want_o" = open ]; then
        [ "$o" = open ] && mark yes "tcp/${p} responds from outside" \
                        || mark no  "tcp/${p} does not respond from outside (${o:-no result}); ${label} must stay reachable"
    else
        [ "$o" != open ] && mark yes "tcp/${p} does not respond from outside (${o:-no result})" \
                         || mark no  "tcp/${p} still responds from outside"
    fi
    if [ "$want_a" = open ]; then
        [ "$a" = open ] && mark yes "tcp/${p} responds from the management subnet" \
                        || mark no  "tcp/${p} does not respond from the management subnet (${a:-no result})"
    else
        [ "$a" != open ] && mark yes "tcp/${p} does not respond from the management subnet (${a:-no result})" \
                         || mark no  "tcp/${p} still responds from the management subnet"
    fi
done
echo

# The service half of the oracle: reachability is not the same as working, and a
# packet filter that lets a SYN through while the service behind it has stopped
# would pass every check above.
if fetch_has "$OUTSIDE_CTN" "http://${SERVER_IP}/" "$PUBLIC_MARKER"; then
    mark yes "the public site serves ${PUBLIC_MARKER} to the outside host"
else
    mark no  "the public site does not serve its page to the outside host"
fi
if fetch_has "$ADMIN_CTN" "http://${SERVER_IP}/" "$PUBLIC_MARKER"; then
    mark yes "the public site serves ${PUBLIC_MARKER} to the management subnet"
else
    mark no  "the public site does not serve its page to the management subnet"
fi

# The credential half. A password must open nothing, and the key must still work.
# The password attempt is made from the management subnet rather than from
# outside, because once the packet filter is in place the outside host cannot
# reach port 22 at all and a refusal there would prove only that the filter
# works, not that sshd would have refused the password.
if ! docker exec "$SERVER_CTN" id -u "$ADMIN_USER" >/dev/null 2>&1; then
    # Without the account this probe proves nothing: the login fails because
    # there is nobody to log in as, not because sshd refuses passwords. Ticking
    # it here would report Part 3 done before Part 2 had started.
    mark no "cannot test the password yet: ${ADMIN_USER} does not exist (Part 2)"
elif ssh_password_login "$ADMIN_CTN" "$ADMIN_USER" "$ADMIN_PASS" "$SERVER_IP"; then
    mark no  "a password still opens a session as ${ADMIN_USER}"
else
    msg="$( ssh_password_message "$ADMIN_CTN" "$ADMIN_USER" "$ADMIN_PASS" "$SERVER_IP" )"
    mark yes "a password opens nothing${msg:+: ${msg##*: }}"
fi
if ssh_password_login "$ADMIN_CTN" root "$ROOT_PASS" "$SERVER_IP"; then
    mark no  "root still logs in with a password"
else
    mark yes "root does not log in with a password"
fi
if docker exec "$ADMIN_CTN" test -f "$ADMIN_KEY" 2>/dev/null; then
    if [ "$( ssh_key_run "$SERVER_IP" 'id -un' )" = "$ADMIN_USER" ]; then
        mark yes "the admin station's key opens a session as ${ADMIN_USER}"
    else
        mark no  "the admin station's key does not open a session as ${ADMIN_USER}"
    fi
else
    mark no  "${ADMIN_CTN} holds no key pair yet"
fi
echo

# ---------------------------------------------------------------------------
echo "== the last few lines sshd logged =="
sshd_log_tail 8 | sed 's/^/  /'
echo

# ---------------------------------------------------------------------------
echo "== where the server is =="
if [ "$fail" -eq 0 ]; then
    echo "  HARDENED    every check passes: the public site serves anyone, SSH responds only to"
    echo "              the management subnet and only to a key, and nothing else responds at all"
elif [ "$fail" -le 4 ]; then
    printf '  NEARLY      %d of %d checks pass. Read the unticked lines; at this point they\n' \
        "$pass" "$((pass+fail))"
    echo "              are a specific setting rather than a missing stage"
else
    printf '  BUILDING    %d of %d checks pass. The first unticked line is the earliest\n' \
        "$pass" "$((pass+fail))"
    echo "              thing to fix, because every later stage is read through it"
fi
