#!/usr/bin/env bash
# Grade the learner's findings against the range that is running.
#
#   scripts/score.sh
#
# It copies /root/findings.txt out of the attacker container, derives ground
# truth from the live containers (scripts/truth.sh), and prints a fixed-format
# head that selftest.sh greps followed by the human breakdown.
#
# It exits 0 whenever grading ran, however low the score. Non-zero means the
# range is not spawned or the findings file is missing, so a red panel in the TUI
# keeps meaning "something is broken" and never "you did badly".
#
# Every category that can be claimed wrongly costs marks, which is what makes a
# submission of everything score below an empty one. The floor is 0, so it cannot
# go negative; the penalties are what make it lose.
set -uo pipefail
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$HERE/lib.sh"
source "$HERE/truth.sh"

range_is_up || {
    echo "This range is not spawned, so there is nothing to grade." >&2
    echo "Run Spawn first. Findings are read out of the attacker container, so a" >&2
    echo "range that has been torn down cannot be scored." >&2
    exit 1
}

truth_load || exit 1

mkdir -p "$STATE_DIR"
docker cp "${ATTACKER_CTN}:${FINDINGS_PATH}" "$FINDINGS_COPY" >/dev/null 2>&1 || {
    echo "no findings file on the attacker; record something with \`report\` first" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# What the range is worth. Every maximum is counted off ground truth, so the
# score is a percentage of what was actually there rather than of a fixed total.

# The segments a scan has to find. The attacker's own is excluded because it is
# on the attacker's own interface, and at easy the one segment the learner was
# handed is excluded as well: it is given, so it is worth nothing.
scored_segments=()
for n in "${T_SEGMENTS[@]}"; do
    in_list "$n" "${T_GIVEN_NETS[@]}" && continue
    scored_segments+=( "$n" )
done

n_seg="${#scored_segments[@]}"
n_rtr="${#T_ROUTER_IPS[@]}"
n_host="${#T_HOSTS[@]}"
n_port="${#T_PORTS[@]}"
n_ver=0
for k in "${T_PORTS[@]}"; do [ -n "${T_VERSION[$k]}" ] && n_ver=$(( n_ver + 1 )); done
n_intel=0
for ip in "${!T_INTEL[@]}"; do
    for t in ${T_INTEL[$ip]}; do n_intel=$(( n_intel + 1 )); done
done
# Every host can be classified, so the category is worth one award per host. It
# is small per host on purpose: a class is inferred from several weak signals and
# a learner who gets two of the four wrong should lose a little, not a section.
n_class=0
for ip in "${!T_CLASS[@]}"; do [ -n "${T_CLASS[$ip]}" ] && n_class=$(( n_class + 1 )); done

# The chain, counted off the tokens that were actually planted rather than off
# the depth the generator drew. A milestone whose planting failed is one nobody
# is marked down for missing, which is the same rule the ports follow: ground
# truth is what the range is holding, not what it meant to hold.
n_flag=0
chain_max=0
for m in "${!T_FLAG_TOKEN[@]}"; do
    n_flag=$(( n_flag + 1 ))
    if [ "$m" = flag ]; then
        chain_max=$(( chain_max + W_FLAG ))
    else
        chain_max=$(( chain_max + ${W_MILESTONE[$m]:-0} ))
    fi
done

max=$(( n_seg * W_SUBNET + n_seg * W_HOPS + n_rtr * W_ROUTER \
      + n_host * W_HOST + n_port * W_PORT + n_port * W_SERVICE \
      + n_ver * W_VERSION + n_intel * W_INTEL + n_class * W_CLASS + chain_max ))

# ---------------------------------------------------------------------------
# Grade the submission. Every finding is reduced to a key first and each key is
# graded once, so recording the same host three times scores it once and a
# learner who re-runs a scan into the same file is not rewarded for the repeat.

declare -A seen=()
got_seg=0 got_hops=0 got_rtr=0 got_host=0 got_port=0 got_svc=0 got_ver=0 got_intel=0 got_class=0
fp_seg=0 fp_rtr=0 fp_host=0 fp_port=0 fp_intel=0 fp_class=0
got_flag=0 flag_lines=0
declare -A got_milestone=()
earned=0

add() { earned=$(( earned + $1 )); }

while read -r kind rest || [ -n "$kind" ]; do
    [ -n "$kind" ] || continue
    case "$kind" in
        net)
            set -- $rest
            cidr="$1"; hops="${3:-}"
            key="net $cidr"
            [ -n "${seen[$key]:-}" ] && continue
            seen["$key"]=1
            # Three subnets are neither credited nor penalised, and all three for
            # the same reason: none of them was found by scanning. What the
            # opening handed over unambiguously; the segment the attacker is
            # standing on; and the vault's subnet, which the survey cannot reach
            # and which the filter in front of it names out loud to anyone who
            # probes it.
            in_list "$cidr" "${T_GIVEN_NETS[@]}" && continue
            [ "$cidr" = "$T_ATT_SUBNET" ] && continue
            [ -n "$T_VAULT_NET" ] && [ "$cidr" = "$T_VAULT_NET" ] && continue
            if in_list "$cidr" "${T_SEGMENTS[@]}"; then
                got_seg=$(( got_seg + 1 )); add "$W_SUBNET"
                # Distance scores only on a segment already found.
                if [ "$hops" = "${T_SEG_HOPS[$cidr]}" ]; then
                    got_hops=$(( got_hops + 1 )); add "$W_HOPS"
                fi
            else
                # A dead range is not a live segment, so claiming one costs the
                # same as inventing a subnet: it is exactly the finding the range
                # is teaching a learner to rule out.
                fp_seg=$(( fp_seg + 1 )); add "-$P_SUBNET"
            fi
            ;;
        router)
            set -- $rest
            ip="$1"; key="router $ip"
            [ -n "${seen[$key]:-}" ] && continue
            seen["$key"]=1
            [ "$ip" = "$T_ATT_GW" ] && continue
            if in_list "$ip" "${T_ROUTER_IPS[@]}"; then
                got_rtr=$(( got_rtr + 1 )); add "$W_ROUTER"
            else
                fp_rtr=$(( fp_rtr + 1 )); add "-$P_ROUTER"
            fi
            ;;
        host)
            set -- $rest
            ip="$1"; key="host $ip"
            [ -n "${seen[$key]:-}" ] && continue
            seen["$key"]=1
            [ "$ip" = "$T_ATTACKER_IP" ] && continue
            if in_list "$ip" "${T_HOSTS[@]}"; then
                got_host=$(( got_host + 1 )); add "$W_HOST"
            elif in_list "$ip" "${T_ROUTER_IPS[@]}" || [ "$ip" = "$T_ATT_GW" ]; then
                # A router interface replies to a sweep, so an accurate scan
                # finds it. Calling it a host is a mislabelling, not an invented
                # address: no credit, and no penalty either.
                :
            else
                fp_host=$(( fp_host + 1 )); add "-$P_HOST"
            fi
            ;;
        port)
            set -- $rest
            ip="$1"; proto="$2"; port="$3"; svc="${4:-}"; shift 3
            [ $# -ge 1 ] && shift        # drop the service field; what is left is the version
            ver="$*"
            key="port ${ip}/${proto}/${port}"
            [ -n "${seen[$key]:-}" ] && continue
            seen["$key"]=1
            tkey="${ip}/${proto}/${port}"
            if in_list "$tkey" "${T_PORTS[@]}"; then
                got_port=$(( got_port + 1 )); add "$W_PORT"
                # Service and version score only on a port that is genuinely
                # open, so a lucky guess about what is behind a closed port is
                # worth nothing.
                if [ -n "$svc" ] && truth_service_matches "$svc" "${T_ACCEPT[$tkey]}"; then
                    got_svc=$(( got_svc + 1 )); add "$W_SERVICE"
                fi
                if [ -n "$ver" ] && truth_version_matches "$ver" "${T_VERSION[$tkey]}"; then
                    got_ver=$(( got_ver + 1 )); add "$W_VERSION"
                fi
            else
                fp_port=$(( fp_port + 1 )); add "-$P_PORT"
            fi
            ;;
        intel)
            set -- $rest
            ip="$1"; tok="${2:-}"
            key="intel ${ip} ${tok}"
            [ -n "${seen[$key]:-}" ] && continue
            seen["$key"]=1
            if [[ " ${T_INTEL[$ip]:-} " == *" $tok "* ]]; then
                got_intel=$(( got_intel + 1 )); add "$W_INTEL"
            else
                fp_intel=$(( fp_intel + 1 )); add "-$P_INTEL"
            fi
            ;;
        class)
            set -- $rest
            ip="$1"; cls="${2:-}"
            key="class $ip"
            [ -n "${seen[$key]:-}" ] && continue
            seen["$key"]=1
            # A router interface is not one of the four classes and is exempt in
            # both directions, the same way it is exempt from the host category:
            # calling it a network device is an accurate observation about an
            # address the range does not classify, and charging for it would
            # punish a correct scan.
            in_list "$ip" "${T_ROUTER_IPS[@]}" && continue
            [ "$ip" = "$T_ATT_GW" ] && continue
            [ "$ip" = "$T_ATTACKER_IP" ] && continue
            if [ -z "${T_CLASS[$ip]:-}" ]; then
                # A class on an address that holds no host costs the same as any
                # other claim about an address that is not there. Without that
                # this category is sprayable: four guesses over a /24 would
                # harvest every server on it at no risk, which is exactly what
                # P_ROUTER and P_INTEL exist to stop elsewhere.
                fp_class=$(( fp_class + 1 )); add "-$P_CLASS"
            elif [ "$cls" = "${T_CLASS[$ip]}" ]; then
                got_class=$(( got_class + 1 )); add "$W_CLASS"
            else
                fp_class=$(( fp_class + 1 )); add "-$P_CLASS"
            fi
            ;;
        flag)
            set -- $rest
            tok="$1"
            key="flag $tok"
            [ -n "${seen[$key]:-}" ] && continue
            seen["$key"]=1
            flag_lines=$(( flag_lines + 1 ))
            # A token is matched against every milestone the range planted, so
            # the learner never has to say which one they think they have. A
            # token that matches nothing scores nothing and costs nothing: an
            # 8-hex-digit string behind a fixed prefix is not something anybody
            # arrives at by guessing, so there is no spraying to deter and a
            # penalty would only punish a typo.
            for m in "${!T_FLAG_TOKEN[@]}"; do
                [ "${T_FLAG_TOKEN[$m]}" = "$tok" ] || continue
                got_flag=$(( got_flag + 1 ))
                got_milestone["$m"]=1
                if [ "$m" = flag ]; then add "$W_FLAG"; else add "${W_MILESTONE[$m]:-0}"; fi
                break
            done
            ;;
    esac
done < "$FINDINGS_COPY"

# ---------------------------------------------------------------------------
score=0
if [ "$max" -gt 0 ] && [ "$earned" -gt 0 ]; then
    score=$(( ( earned * 100 + max / 2 ) / max ))
fi
[ "$score" -lt "$SCORE_FLOOR" ] && score="$SCORE_FLOOR"
[ "$score" -gt 100 ] && score=100

elapsed=""
par="${TIER_PAR[$T_TIER]:-0}"
if [ -n "$T_SPAWNED_AT" ]; then
    secs=$(( $( date +%s ) - T_SPAWNED_AT ))
    elapsed="$( printf '%d:%02d' $(( secs / 60 )) $(( secs % 60 )) )"
fi
par_str="$( printf '%d:%02d' $(( par / 60 )) $(( par % 60 )) )"

echo "SEED ${T_SEED} TIER ${T_TIER} SHAPE ${T_SHAPE} MUTATOR ${T_MUTATOR}"
echo "SCORE ${score} / 100"
printf 'MAP    subnets %d/%d  hops %d/%d  routers %d/%d\n' \
    "$got_seg" "$n_seg" "$got_hops" "$n_seg" "$got_rtr" "$n_rtr"
printf 'HOSTS %d/%d  PORTS %d/%d  SERVICES %d/%d  VERSIONS %d/%d  INTEL %d/%d  CLASSES %d/%d\n' \
    "$got_host" "$n_host" "$got_port" "$n_port" "$got_svc" "$n_port" \
    "$got_ver" "$n_ver" "$got_intel" "$n_intel" "$got_class" "$n_class"
printf 'FALSE POSITIVES subnets %d  routers %d  hosts %d  ports %d  intel %d  classes %d\n' \
    "$fp_seg" "$fp_rtr" "$fp_host" "$fp_port" "$fp_intel" "$fp_class"

# The chain, deepest milestone first, so the one line says how far in the learner
# got rather than only how many tokens they held.
deepest="nowhere"
for m in "${CHAIN_MILESTONES[@]}" flag; do
    [ -n "${got_milestone[$m]:-}" ] && deepest="$m"
done
[ "$deepest" = flag ] && deepest="the flag"
printf 'CHAIN %d/%d  reached: %s\n' "$got_flag" "$n_flag" "$deepest"

[ -n "$elapsed" ] && echo "ELAPSED ${elapsed} (par ${par_str})"

echo
echo "  Points come from what you found, in the proportions the field manual"
echo "  prints. This range was worth ${max} raw points; you took ${earned}."
echo "  Reveal now works: it prints the whole key beside what you submitted."
if [ "$( wc -l < "$FINDINGS_COPY" )" -eq 0 ]; then
    echo
    echo "  Your findings file is empty. Record findings on the attacker with"
    echo "  \`report\`, then run Score again."
fi

# Append one line per grading. Local and unsigned; collecting attempts for
# marking is out of scope until someone asks for it.
printf '%s seed=%s tier=%s shape=%s mutator=%s opening=%s score=%s chain=%s/%s elapsed=%s par=%s\n' \
    "$( date -u +%Y-%m-%dT%H:%M:%SZ )" "$T_SEED" "$T_TIER" "$T_SHAPE" "${T_MUTATOR:-?}" "${T_OPENING:-?}" \
    "$score" "$got_flag" "$n_flag" "${elapsed:-?}" "$par_str" \
    >> "$ATTEMPTS_LOG"

# Reveal refuses to print anything until this exists. generate.sh clears it, so
# the marker always belongs to the range that is running.
: > "$SCORED_MARKER"
exit 0
