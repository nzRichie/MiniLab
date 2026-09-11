#!/usr/bin/env bash
# Print the key for the range that is running, beside what the learner submitted.
#
#   scripts/reveal.sh
#
# It refuses to print anything until Score has run at least once against this
# spawn. generate.sh clears the marker and score.sh writes it, so the gate always
# refers to the range in front of the learner: a fresh range locks Reveal again.
#
# THE LOCK IS A SPEED BUMP, NOT A CONTROL, and it is worth saying so plainly
# rather than letting a later author mistake it for one. Score works on an empty
# submission, so anyone who wants the key can unlock it in one action. And
# generate.sh has to ship, because spawn.sh calls it, so a determined learner can
# re-run it with the seed that Status prints and read the drawn range straight
# out of state/topology.env. What the lock buys is that the key is not the first
# thing on the menu, which is the whole of what it is for: the range is something
# a learner replays as often as they like, not a proctored examination. If a
# proctored mode is ever wanted, the seed has to stop being printed and the
# grading has to move off the learner's own machine.
#
# Like score.sh, every fact here is read back off the live containers rather than
# out of state/topology.env, so what is revealed is the network the learner
# actually scanned.
set -uo pipefail
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$HERE/lib.sh"
source "$HERE/truth.sh"

range_is_up || {
    echo "This range is not spawned, so there is no key to print." >&2
    exit 1
}

if [ ! -f "$SCORED_MARKER" ]; then
    echo "Reveal is locked until you have run Score at least once on this range."
    echo
    echo "Record what you found on the attacker with \`report\`, run the Score"
    echo "action, and then come back here. Score works on an empty submission"
    echo "too, so an attempt you are unhappy with still unlocks the key."
    exit 1
fi

truth_load || exit 1

# What the learner submitted, so each line of the key can say whether they had
# it. score.sh copied it out at grading time; this reads the same copy, so Reveal
# describes the submission that was graded rather than one edited since.
declare -A sub=()
if [ -f "$FINDINGS_COPY" ]; then
    while read -r kind rest || [ -n "$kind" ]; do
        [ -n "$kind" ] || continue
        set -- $rest
        case "$kind" in
            net)    sub["net $1"]="${3:-}" ;;
            router) sub["router $1"]=1 ;;
            host)   sub["host $1"]=1 ;;
            port)
                # The whole tail is kept, not just the next two fields: a learner
                # who wrote "ftp vsftpd 3.0.5" gave the version in fields five and
                # six, and truncating it here would report a correct version as
                # wrong in the key while score.sh had already credited it.
                ip="$1"; proto="$2"; pn="$3"; shift 3
                sub["port ${ip}/${proto}/${pn}"]="$*"
                ;;
            intel)  sub["intel $1 ${2:-}"]=1 ;;
            class)  sub["class $1"]="${2:-}" ;;
            flag)   sub["flag $1"]=1 ;;
        esac
    done < "$FINDINGS_COPY"
fi

mark() { [ -n "${sub[$1]:-}" ] && printf 'you had it' || printf 'MISSED'; }

echo "SEED ${T_SEED} TIER ${T_TIER} SHAPE ${T_SHAPE} MUTATOR ${T_MUTATOR}"
echo "The estate was ${T_ORG}."
echo "Reproduce this exact range with Spawn at tier ${T_TIER} and seed ${T_SEED}."
echo

echo "== the map =="
printf '  %-20s %-18s %-6s %s\n' 'you were at' "$T_ATTACKER_IP" '' "on ${T_ATT_SUBNET}, gateway ${T_ATT_GW}"
echo "  (neither the segment you stood on nor your own gateway was worth marks)"
echo
for n in "${T_SEGMENTS[@]}"; do
    tag="$( mark "net $n" )"
    hops_note=""
    if [ -n "${sub[net $n]:-}" ] && [ "${sub[net $n]}" != "${T_SEG_HOPS[$n]}" ]; then
        hops_note="  (you said ${sub[net $n]:-no} hops)"
    fi
    in_list "$n" "${T_GIVEN_NETS[@]}" && tag="handed to you at spawn; worth nothing"
    printf '  %-18s %d hop(s)  gateway %-16s  %s%s\n' \
        "$n" "${T_SEG_HOPS[$n]}" "${T_SEG_GW[$n]}" "$tag" "$hops_note"
done
for n in "${T_DEAD[@]}"; do
    tag="you did not claim it"
    [ -n "${sub[net $n]:-}" ] && tag="YOU CLAIMED IT, which cost you ${P_SUBNET} points"
    printf '  %-18s routed and empty; no host in it     %s\n' "$n" "$tag"
done
echo
echo "== router interfaces =="
for ip in "${T_ROUTER_IPS[@]}"; do
    printf '  %-18s %s\n' "$ip" "$( mark "router $ip" )"
done
echo
echo "== the hosts =="
for ip in "${T_HOSTS[@]}"; do
    printf '  %-18s on %-18s ping: %-8s shut ports: %-9s %s\n' \
        "$ip" "${T_HOST_SEG[$ip]}" "${T_ICMP[$ip]}" "${T_SHUT[$ip]}" "$( mark "host $ip" )"
    if [ -n "${T_CLASS[$ip]:-}" ]; then
        cdetail="not classified"
        if [ -n "${sub[class $ip]:-}" ]; then
            [ "${sub[class $ip]}" = "${T_CLASS[$ip]}" ] \
                && cdetail="you said ${sub[class $ip]}, right" \
                || cdetail="you said ${sub[class $ip]}, wrong"
        fi
        printf '      class      %-19s %s\n' "${T_CLASS[$ip]}" "$cdetail"
    fi
    if [ -n "${T_FILTERED[$ip]:-}" ]; then
        printf '      filtered   %-19s dropped rather than refused; not open\n' \
            "$( echo "${T_FILTERED[$ip]}" | tr ' ' ',' )"
    fi
    for k in "${T_PORTS[@]}"; do
        [ "${k%%/*}" = "$ip" ] || continue
        rest="${k#*/}"; proto="${rest%%/*}"; port="${rest#*/}"
        detail="$( mark "port $k" )"
        if [ -n "${sub[port $k]:-}" ]; then
            said_svc="${sub[port $k]%% *}"
            said_ver="${sub[port $k]#* }"
            [ "$said_ver" = "$said_svc" ] && said_ver=""
            truth_service_matches "$said_svc" "${T_ACCEPT[$k]}" \
                && detail="$detail, service right" || detail="$detail, service wrong"
            if [ -n "${T_VERSION[$k]}" ]; then
                truth_version_matches "$said_ver" "${T_VERSION[$k]}" \
                    && detail="$detail, version right" || detail="$detail, version wrong"
            fi
        fi
        printf '      %-10s %-8s %-10s %s\n' \
            "${proto}/${port}" "${T_SERVICE[$k]}" "${T_VERSION[$k]:--}" "$detail"
    done
    if [ -n "${T_INTEL[$ip]:-}" ]; then
        for t in ${T_INTEL[$ip]}; do
            printf '      intel      %-19s %s\n' "$t" "$( mark "intel $ip $t" )"
        done
    fi
done
echo
echo "== the way in =="
if [ "${#T_FLAG_TOKEN[@]}" -eq 0 ]; then
    echo "  This range planted no chain."
else
    echo "  ${T_DEPTH} layers. Every door on it opens because of a configuration"
    echo "  a defender fixes by editing a file; none of it is an exploit."
    echo
    for m in "${CHAIN_MILESTONES[@]}" flag; do
        tok="${T_FLAG_TOKEN[$m]:-}"
        [ -n "$tok" ] || continue
        printf '  %-10s %-34s %s\n' "$m" "$tok" "$( mark "flag $tok" )"
    done
    echo
    echo "  How it was walked:"
    echo "   1. The telnet host names a device family in its login prompt. Either"
    echo "      the credential that family ships with is still set, or the shared"
    echo "      operations account is there with a password out of the wordlist."
    echo "      Which services on this range name that account is drawn per spawn,"
    echo "      and more than one of them does above the easy tier. Either"
    echo "      credential is a shell, and the foothold token is in that"
    echo "      account's home directory."
    if [ -n "$T_VAULT_NET" ]; then
        echo "   2. That home directory also holds a passphrase-protected SSH key"
        echo "      and a note saying where it goes. The passphrase is NOT on that"
        echo "      machine: it is on one of the services this range drew to carry"
        echo "      it, which may be the anonymous share, an unauthenticated"
        echo "      key-value store, a backup module or a retained message on a"
        echo "      broker. One half without the other opens nothing, and the two"
        echo "      are found by completely different work."
        if [ "$T_DEPTH" -ge 4 ]; then
            echo "   3. The key opens an account on the SSH host, which is the only"
            echo "      address the filter in front of ${T_VAULT_NET} lets through."
            echo "   4. From there the same key opens the machine on ${T_VAULT_NET},"
            echo "      and \`sudo -l\` on it names the one command that reads the flag."
        else
            echo "   3. The key opens the machine on ${T_VAULT_NET}, which the filter"
            echo "      on its router reaches only from the telnet host. Probing it"
            echo "      from anywhere else answers ICMP administratively-prohibited,"
            echo "      which is the breadcrumb saying the door is there."
            echo "   4. \`sudo -l\` on it names the one command that reads the flag."
        fi
    else
        echo "   2. \`sudo -l\` in that shell names the one command the account may"
        echo "      run as root, and that command reads the file the flag is in."
    fi
fi

echo
echo "== what you did not get =="
missed=0
for n in "${T_SEGMENTS[@]}"; do
    in_list "$n" "${T_GIVEN_NETS[@]}" && continue
    [ -n "${sub[net $n]:-}" ] || { echo "  segment $n, ${T_SEG_HOPS[$n]} hop(s) away"; missed=1; }
done
for ip in "${T_ROUTER_IPS[@]}"; do
    [ -n "${sub[router $ip]:-}" ] || { echo "  router interface $ip"; missed=1; }
done
for ip in "${T_HOSTS[@]}"; do
    [ -n "${sub[host $ip]:-}" ] || {
        note=""
        [ "${T_ICMP[$ip]}" = silent ] && note=" (it drops echo requests; a TCP probe finds it)"
        echo "  host $ip${note}"; missed=1; }
done
for k in "${T_PORTS[@]}"; do
    [ -n "${sub[port $k]:-}" ] || { echo "  open port $k (${T_SERVICE[$k]})"; missed=1; }
done
for ip in "${!T_INTEL[@]}"; do
    for t in ${T_INTEL[$ip]}; do
        [ -n "${sub[intel $ip $t]:-}" ] || { echo "  intel $t on $ip"; missed=1; }
    done
done
for m in "${CHAIN_MILESTONES[@]}" flag; do
    tok="${T_FLAG_TOKEN[$m]:-}"
    [ -n "$tok" ] || continue
    [ -n "${sub[flag $tok]:-}" ] || { echo "  the $m token"; missed=1; }
done
for ip in "${T_HOSTS[@]}"; do
    [ -n "${T_CLASS[$ip]:-}" ] || continue
    [ -n "${sub[class $ip]:-}" ] || { echo "  the class of $ip (${T_CLASS[$ip]})"; missed=1; }
done
[ "$missed" -eq 0 ] && echo "  nothing. You found the whole range."
echo
echo "Regenerate draws a fresh range at the same tier."
