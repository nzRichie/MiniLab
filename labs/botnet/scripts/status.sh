#!/usr/bin/env bash
# The lab's oracle. Prints, in one screen, every count the handout's questions
# read: the controller's roster, the loader's recruitment log, the number of
# results the population has returned, whether the inside account has been
# guessed, the admin workstation's two probes, and the router's current filter.
#
# It withholds nothing. The learner is not being graded on FINDING the bots --
# they are the ones running them -- so unlike the beaconing lab's status, this
# one shows the whole population and its whole record. What it does not print is
# the one thing that is an answer: which field hosts hold the second credential,
# which is nowhere in any count and only in solution/.
#
# Runs with hold = true in the TUI, so the learner reads it rather than watching
# it scroll past.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

running "$ROUTER_CTN" || {
    echo "The lab is not running ($ROUTER_CTN is not up). Spawn it first." >&2
    exit 1
}

rule() { printf '%s\n' "----------------------------------------------------------------------"; }

# --- the controller and the population ------------------------------------
rule
if c2_running; then
    echo "CONTROLLER: running on the c2 (tcp/${C2_PORT})"
    echo
    c2_cmd status
else
    echo "CONTROLLER: not running."
    echo "  Start it on the c2:  docker exec -it $C2_CTN c2"
    echo "  Until it is up, no bot can register and this roster is empty."
fi

# --- the loader's recruitment record --------------------------------------
rule
fetches="$( payload_fetches )"
echo "LOADER: the payload (bot.py) has been fetched ${fetches:-0} time(s)."
if [ "${fetches:-0}" -gt 0 ]; then
    echo "  In order, each fetch and the field address that made it:"
    payload_fetch_log | awk '{ printf "    %s  %s\n", $4, $1 }' | sed 's/[][]//g'
fi

# --- what the population has returned --------------------------------------
rule
results="$( result_count )"
echo "RESULTS: the controller holds ${results:-0} non-empty result file(s)."

# --- the inside server: has the account fallen? ---------------------------
rule
if account_guessed; then
    echo "INSIDE SERVER: the ${SERVER_USER} account HAS been logged into from a field"
    echo "  address. Password failures logged so far: $( failed_attempts )."
    echo "  Failures per source address:"
    failed_by_source | sed 's/^/    /'
else
    fa="$( failed_attempts )"
    if [ "${fa:-0}" -gt 0 ]; then
        echo "INSIDE SERVER: the ${SERVER_USER} account has NOT been logged into."
        echo "  Password failures logged so far: ${fa}. Failures per source:"
        failed_by_source | sed 's/^/    /'
    else
        echo "INSIDE SERVER: no login attempts against ${SERVER_USER} yet."
    fi
fi

# --- the admin: is the network still working for the site? ----------------
rule
echo "ADMIN WORKSTATION (the collateral-damage check):"
w="$( admin_web_state )"; s="$( admin_ssh_state )"
if admin_web_ok; then echo "  web fetch of the server page:  OK   (${w:-no reading yet})"
else                  echo "  web fetch of the server page:  FAIL (${w:-no reading yet})"; fi
if admin_ssh_ok; then echo "  ssh login to the server:       OK   (${s:-no reading yet})"
else                  echo "  ssh login to the server:       FAIL (${s:-no reading yet})"; fi

# --- the router's policy --------------------------------------------------
rule
n="$( router_rule_count )"
if [ "${n:-0}" -gt 0 ]; then
    echo "ROUTER: ${n} rule(s) in the FORWARD chain:"
    router_rules | sed 's/^/    /'
else
    echo "ROUTER: no filtering. Every leg forwards to every other."
fi
rule
