#!/usr/bin/env bash
# Print the lab's state and its own success oracle, so the learner reads what
# changed without shelling into six containers.
#
# It reads state and changes nothing. Every probe it runs comes from lib.sh, so
# what this prints and what selftest.sh asserts cannot drift apart.
#
# The oracle has five parts, one per part of the handout:
#
#   1  every machine in the site answers a sweep from outside it
#   2  only the bastion answers, and only on 22
#   3  a session opened through the bastion arrives at the inner host FROM THE
#      BASTION'S ADDRESS, which is what every restriction in Parts 4 and 5 is
#      written against
#   4  a password opens nothing, each key opens one account, and the jump host
#      forwards only to the destinations it lists
#   5  a key used from an address its authorized_keys entry does not name is
#      refused with the correct key in hand, and a forced-command key runs its
#      command whatever the client asked for
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

hr()  { printf '%s\n' "------------------------------------------------------------"; }
sec() { echo; hr; echo "$*"; hr; }
yn()  { if [ "$1" = yes ]; then echo yes; else echo no; fi; }

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

if ! running "$EDGE_CTN"; then
    echo "The lab is not running ($EDGE_CTN is not up)."
    echo "Start it with the Spawn action, or scripts/spawn.sh."
    exit 1
fi

sec "Containers"
for ctn in "$WS_CTN" "$EDGE_CTN" "$BASTION_CTN" "$APP_CTN" "$DB_CTN" "$SW_CTN"; do
    if running "$ctn"; then printf '  %-32s up\n' "$ctn"
    else                    printf '  %-32s DOWN\n' "$ctn"; fi
done

# ---------------------------------------------------------------------------
sec "The edge router's packet filter"
ruleset="$( nft_ruleset )"
if [ -z "$ruleset" ]; then
    echo "  no ruleset: nothing is registered at any hook, so nothing is examined"
else
    printf '%s\n' "$ruleset" | sed 's/^/  /'
fi
echo
if forward_policy_is_drop; then
    echo "  forward hook: a base chain is registered and its policy is drop"
else
    echo "  forward hook: no base chain with policy drop -> everything is forwarded"
fi

# ---------------------------------------------------------------------------
sec "Sweep from the workstation ($WS_IP), ports $SWEEP_PORTS"
echo "  open     = a listener replied"
echo "  closed   = the host replied with a TCP reset: nothing is listening there"
echo "  filtered = nothing replied at all, which is what a drop rule looks like"
for pair in "bastion $BASTION_IP" "app $APP_IP" "db $DB_IP"; do
    set -- $pair
    echo
    printf '  %s (%s)\n' "$1" "$2"
    sweep "$WS_CTN" "$2" | sed 's/^/    /'
done

# ---------------------------------------------------------------------------
sec "Who each machine will accept, and how"
printf '  %-10s %-24s %-22s %s\n' machine PasswordAuthentication PermitRootLogin PermitOpen
for pair in "bastion $BASTION_CTN" "app $APP_CTN" "db $DB_CTN"; do
    set -- $pair
    printf '  %-10s %-24s %-22s %s\n' "$1" \
        "$( sshd_config_value "$2" PasswordAuthentication )" \
        "$( sshd_config_value "$2" PermitRootLogin )" \
        "$( sshd_config_value "$2" PermitOpen )"
done
echo
echo "  Read against a source address, so a Match block is resolved rather than guessed:"
printf '  %-10s %-34s %s\n' machine "pubkey from the bastion ($BASTION_IP)" "pubkey from app ($APP_IP)"
for pair in "app $APP_CTN $APP_USER" "db $DB_CTN $DB_USER"; do
    set -- $pair
    printf '  %-10s %-34s %s\n' "$1" \
        "$( sshd_match_value "$2" PubkeyAuthentication "$BASTION_IP" "$3" )" \
        "$( sshd_match_value "$2" PubkeyAuthentication "$APP_IP" "$3" )"
done

# ---------------------------------------------------------------------------
sec "What each account's key is allowed to do"
echo "  The key body is cut out; what is left is the option list on the entry."
for triple in "bastion:$JUMP_USER $BASTION_CTN $JUMP_USER" \
              "app:$APP_USER $APP_CTN $APP_USER" \
              "db:$DB_USER $DB_CTN $DB_USER" \
              "db:$REPORT_USER $DB_CTN $REPORT_USER"; do
    set -- $triple
    opts="$( authorized_keys_options "$2" "$3" )"
    if [ -z "$( authorized_keys_file "$2" "$3" )" ]; then
        printf '  %-18s no key installed\n' "$1"
    elif [ -z "$opts" ]; then
        printf '  %-18s a key, with no options: usable from anywhere, for anything\n' "$1"
    else
        printf '  %-18s %s\n' "$1" "$opts"
    fi
done

# ---------------------------------------------------------------------------
sec "The oracle"

# 1/2 -- can the outside reach past the bastion at all?
direct_ssh=no
port_state "$WS_CTN" "$APP_IP" "$SSH_PORT" | grep -q open && direct_ssh=yes
bastion_ssh=no
port_state "$WS_CTN" "$BASTION_IP" "$SSH_PORT" | grep -q open && bastion_ssh=yes
web_out=no
fetch_has "$WS_CTN" "http://$APP_IP/" "$WEB_MARKER" && web_out=yes

printf '  %-56s %s\n' "workstation reaches app on $SSH_PORT directly"        "$( yn $direct_ssh )"
printf '  %-56s %s\n' "workstation reaches the bastion on $SSH_PORT"          "$( yn $bastion_ssh )"
printf '  %-56s %s\n' "workstation reaches app's web service on $WEB_PORT"    "$( yn $web_out )"

# 3 -- a password still opens an inner host directly?
pw_direct=no
ssh_password_login "$WS_CTN" "$APP_USER" "$APP_PASS" "$APP_IP" && pw_direct=yes
pw_bastion=no
ssh_password_login "$WS_CTN" "$JUMP_USER" "$JUMP_PASS" "$BASTION_IP" && pw_bastion=yes
printf '  %-56s %s\n' "a password opens $APP_USER on app, directly"           "$( yn $pw_direct )"
printf '  %-56s %s\n' "a password opens $JUMP_USER on the bastion"            "$( yn $pw_bastion )"

# 4 -- do the keys work through the bastion?
jump_app=no
[ -n "$( docker exec "$WS_CTN" sh -c "[ -f '$APP_KEY' ] && echo x" 2>/dev/null )" ] \
    && ssh_jump_login "$APP_USER" "$APP_KEY" "$APP_IP" && jump_app=yes
jump_db=no
[ -n "$( docker exec "$WS_CTN" sh -c "[ -f '$DB_KEY' ] && echo x" 2>/dev/null )" ] \
    && ssh_jump_login "$DB_USER" "$DB_KEY" "$DB_IP" && jump_db=yes
printf '  %-56s %s\n' "$APP_USER's key opens app through the bastion"         "$( yn $jump_app )"
printf '  %-56s %s\n' "$DB_USER's key opens db through the bastion"           "$( yn $jump_db )"

# The address the inner hosts last saw a login arrive from. Empty until one has.
for pair in "app $APP_CTN $APP_USER" "db $DB_CTN $DB_USER"; do
    set -- $pair
    src="$( last_accepted_from "$2" "$3" )"
    printf '  %-56s %s\n' "$1 last accepted $3 from" "${src:-<no login yet>}"
done

# 5 -- the lateral path, which no rule on the router can see.
lateral=n/a
if [ -n "$( docker exec "$DB_CTN" sh -c "[ -f '$LEAKED_APP_KEY' ] && echo x" 2>/dev/null )" ]; then
    if ssh_direct_key_login "$DB_CTN" "$APP_USER" "$LEAKED_APP_KEY" "$APP_IP"; then lateral=yes; else lateral=no; fi
    printf '  %-56s %s\n' "the copied key on db opens $APP_USER on app" "$lateral"
else
    printf '  %-56s %s\n' "a copy of $APP_USER's key on db" "not present"
fi
if [ -n "$( docker exec "$APP_CTN" sh -c "[ -f '$LEAKED_DB_KEY' ] && echo x" 2>/dev/null )" ]; then
    if ssh_direct_key_login "$APP_CTN" "$DB_USER" "$LEAKED_DB_KEY" "$DB_IP"; then lat2=yes; else lat2=no; fi
    printf '  %-56s %s\n' "the copied key on app opens $DB_USER on db" "$lat2"
else
    printf '  %-56s %s\n' "a copy of $DB_USER's key on app" "not present"
fi

# The forced command, if a key has been installed for it.
if [ -n "$( authorized_keys_file "$DB_CTN" "$REPORT_USER" )" ]; then
    out="$( ssh_jump_run "$REPORT_USER" "$REPORT_KEY" "$DB_IP" uptime )"
    if printf '%s' "$out" | grep -q "$REPORT_MARKER"; then
        printf '  %-56s %s\n' "$REPORT_USER asked for uptime and got" "the report"
    else
        printf '  %-56s %s\n' "$REPORT_USER asked for uptime and got" "something else"
    fi
fi

echo
echo "  The lab is finished when the workstation reaches the bastion on $SSH_PORT and"
echo "  nothing else, both keys open their own account through the bastion, no"
echo "  password opens anything, and the key copied onto db is refused by app."
echo
