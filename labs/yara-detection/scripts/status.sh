#!/usr/bin/env bash
# Print the lab's state and its success oracle.
#
# Four things, in the order the handout works through them: whether the lab is
# up, whether the rule file compiles, what it scores on the corpus and on the
# holdout, and what the scanner does with the two uploads. The holdout half is
# the only way a learner sees anything about those ten files: it prints two
# counts and never names a file.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

hr() { printf '%s\n' "------------------------------------------------------------"; }

echo "YARA rule authoring and generalisation -- lab status"
hr

# --- containers ------------------------------------------------------------
up=0
# S1 is the switch and holds no address, so ip_of prints nothing for it.
for role in workstation scanner client holdout S1; do
    ctn="$( ctn_of "$role" )"
    if running "$ctn"; then
        printf '  %-12s up    %s\n' "$role" "$( ip_of "$role" )"
        up=$(( up + 1 ))
    else
        printf '  %-12s DOWN\n' "$role"
    fi
done
if [ "$up" -lt 5 ]; then
    hr
    echo "The lab is not fully up. Run Spawn first."
    exit 0
fi

# --- the corpus ------------------------------------------------------------
hr
a_count="$( docker exec "$WORKSTATION_CTN" sh -c "ls -1 $CORPUS_SET_A/*.exe | wc -l" 2>/dev/null )"
b_count="$( docker exec "$WORKSTATION_CTN" sh -c "ls -1 $CORPUS_SET_B/*.exe | wc -l" 2>/dev/null )"
echo "Corpus on the workstation"
printf '  %-22s %s files\n' "$CORPUS_SET_A" "$a_count"
printf '  %-22s %s files\n' "$CORPUS_SET_B" "$b_count"

# --- the rule file ---------------------------------------------------------
hr
echo "Your rule file: $RULES_FILE (on the workstation)"
if ! rules_present; then
    echo "  not written yet."
    echo
    echo "Write one, then run Status again. Nothing below can be scored until you do."
    exit 0
fi
if ! rules_compile; then
    echo "  does not compile. yara says:"
    rules_error | sed 's/^/    /'
    exit 0
fi
nrules="$( docker exec "$WORKSTATION_CTN" sh -c "grep -cE '^[[:space:]]*(private[[:space:]]+)?(global[[:space:]]+)?rule[[:space:]]' '$RULES_FILE'" 2>/dev/null )"
echo "  compiles. $nrules rule(s)."

# --- the corpus score ------------------------------------------------------
hr
stage_rules "$WORKSTATION_CTN" || { echo "could not stage the rule file for scoring" >&2; exit 1; }
corpus_out="$( score_dir "$WORKSTATION_CTN" "$CORPUS_DIR" glob )"
read -r c_tp c_fp c_fam c_ben <<<"$( printf '%s\n' "$corpus_out" | head -1 )"
echo "Corpus  (the thirty files you can read)"
printf '  family builds matched   %s / %s\n' "$c_tp" "$c_fam"
printf '  benign files matched    %s   (allowed: %s)\n' "$c_fp" "$CORPUS_FP_ALLOWED"
printf '%s\n' "$corpus_out" | sed -n 's/^FP /  false positive: /p'

# --- the holdout score -----------------------------------------------------
hr
stage_rules "$HOLDOUT_CTN" || { echo "could not stage the rule file on the holdout" >&2; exit 1; }
hold_out="$( score_dir "$HOLDOUT_CTN" "$HOLDOUT_DIR" truthfile )"
read -r h_tp h_fp h_fam h_ben <<<"$( printf '%s\n' "$hold_out" | head -1 )"
echo "Holdout (ten files you cannot read; counts only, no names)"
printf '  family builds matched   %s / %s\n' "$h_tp" "$h_fam"
printf '  benign files matched    %s   (allowed: %s)\n' "$h_fp" "$HOLDOUT_FP_ALLOWED"

# --- Part 4 ----------------------------------------------------------------
hr
echo "Scanner (Part 4)"
v_mal=""; v_ben=""
if ! deployed_present; then
    echo "  no database at $DEPLOYED_DB. Every upload comes back SCANNER ERROR."
else
    printf '  database at %s, %s byte(s)\n' "$DEPLOYED_DB" \
        "$( docker exec "$SCANNER_CTN" stat -c %s "$DEPLOYED_DB" 2>/dev/null )"
    for f in "$UPLOAD_MALICIOUS" "$UPLOAD_BENIGN"; do
        reply="$( upload "$f" )"
        printf '  upload %-20s %s\n' "$f" "$( printf '%s\n' "$reply" | grep -vE '^LibClamAV' | head -1 )"
        # clamscan's loader writes its complaints to standard error and the CGI
        # copies them into the reply. A database it could not parse leaves it
        # scanning with no signatures, and it calls the file clean, so these
        # lines are the only thing that separates "your rule did not match" from
        # "your rule was never loaded".
        printf '%s\n' "$reply" | sed -n 's/^LibClamAV/    LibClamAV/p'
        case "$f" in
            "$UPLOAD_MALICIOUS") v_mal="$( printf '%s\n' "$reply" | verdict_of )" ;;
            "$UPLOAD_BENIGN")    v_ben="$( printf '%s\n' "$reply" | verdict_of )" ;;
        esac
    done
fi

# --- the verdict -----------------------------------------------------------
hr
# Two marks, and the second one only becomes reachable in Part 4. Parts 1 to 3
# are graded on the two scores; Part 4 is graded on the pair of uploads, and
# both halves of that pair count, because a database that rejects everything
# passes the first upload and fails the second.
rules_pass=yes
[ "${c_tp:-0}" -ge "$CORPUS_TP_REQUIRED" ]  || rules_pass=no
[ "${c_fp:-1}" -le "$CORPUS_FP_ALLOWED" ]   || rules_pass=no
[ "${h_tp:-0}" -ge "$HOLDOUT_TP_REQUIRED" ] || rules_pass=no
[ "${h_fp:-1}" -le "$HOLDOUT_FP_ALLOWED" ]  || rules_pass=no

if [ "$rules_pass" = yes ]; then
    echo "RULE   PASS  ${c_tp}/${c_fam} on the corpus and ${h_tp}/${h_fam} on the holdout, no false positive in either."
else
    echo "RULE   NOT YET  the mark is ${CORPUS_TP_REQUIRED}/${c_fam} on the corpus and ${HOLDOUT_TP_REQUIRED}/${h_fam} on the"
    echo "                holdout, with no false positive in either."
fi

if [ "$v_mal" = REJECTED ] && [ "$v_ben" = ACCEPTED ]; then
    echo "SCANNER PASS  $UPLOAD_MALICIOUS rejected, $UPLOAD_BENIGN accepted."
elif [ -z "$v_mal$v_ben" ]; then
    echo "SCANNER NOT YET  nothing is deployed to $DEPLOYED_DB."
else
    echo "SCANNER NOT YET  the mark is $UPLOAD_MALICIOUS rejected AND $UPLOAD_BENIGN accepted."
fi
