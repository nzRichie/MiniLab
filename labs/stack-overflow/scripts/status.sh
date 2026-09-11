#!/usr/bin/env bash
# Print the lab's state and its own success oracle, so the learner reads what
# each build changed without shelling into the appliance.
#
# The oracle is two facts held at once. A build has done its job when the
# exploit no longer reaches the function that prints the recovery key AND the
# service still answers a legitimate registration. Either one alone is easy: a
# service that is not running leaks nothing, and a service that is running with
# the vulnerable build answers everything.
#
# It reads state and it does not grade anything the learner is marked on. Two of
# its probes do send the overflow, because what an overflow can currently do is
# the question the whole of Part 2 answers; neither leaves anything behind, so
# running Status repeatedly does not change the lab.
#
# Every probe comes from lib.sh, so what this prints and what selftest.sh
# asserts cannot drift apart.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

hr()  { printf '%s\n' "------------------------------------------------------------"; }
sec() { echo; hr; echo "$*"; hr; }
mark() { if [ "$1" = yes ]; then printf '  [done] '; else printf '  [    ] '; fi; }

if ! running "$SVC_CTN"; then
    echo "The lab is not running ($SVC_CTN is not up)."
    echo "Start it with the Spawn action, or scripts/spawn.sh."
    exit 1
fi

sec "Containers"
for ctn in "$SVC_CTN" "$OPS_CTN" "$ATTACKER_CTN" "$SW_CTN"; do
    if running "$ctn"; then printf '  %-28s up\n' "$ctn"
    else                    printf '  %-28s DOWN\n' "$ctn"; fi
done

if ! service_running; then
    echo
    echo "  No build of ${SERVICE_NAME} is running on $SVC_CTN, so the service answers"
    echo "  nothing. Run the Reset action to put the appliance back to its starter"
    echo "  state, or start the build you were testing again."
    exit 0
fi

bin="$( service_binary )"

# ---------------------------------------------------------------------------
sec "The build the appliance is running"
printf '  %-46s %s\n' "binary" "$bin"
printf '  %-46s %s\n' "address-space randomisation off for it" "$( service_aslr_off )"

base="$( load_base )"
printf '  %-46s 0x%s\n' "mapped at" "${base:-????}"

off="$( ret_offset "$bin" )"
printf '  %-46s %s bytes\n' "array to saved return address" "${off:-unknown}"

waddr="$( win_runtime_addr )"
printf '  %-46s 0x%s\n' "${WIN_SYMBOL}() sits at" "${waddr:-????}"

# ---------------------------------------------------------------------------
sec "Which hardening reached this build"
printf '  %-46s %s\n' "stack canary (-fstack-protector-*)"   "$( elf_canary "$bin" )"
printf '  %-46s %s\n' "position independent (-fPIE -pie)"    "$( elf_pie "$bin" )"
printf '  %-46s %s\n' "RELRO (-Wl,-z,relro,-z,now)"          "$( elf_relro "$bin" )"

fort="$( elf_fortify_symbols "$bin" )"
printf '  %-46s %s\n' "checked libc calls (-D_FORTIFY_SOURCE)" "${fort:-none}"

echo
echo "  Each line is read out of the file itself, not out of the command that"
echo "  produced it, so a flag that was typed and had no effect shows here as"
echo "  having had none."

# ---------------------------------------------------------------------------
sec "Builds present on the appliance"
docker exec "$SVC_CTN" sh -c "ls -1 '$BIN_DIR' 2>/dev/null" 2>/dev/null | tr -d '\r' | sed 's/^/  /'

# ---------------------------------------------------------------------------
sec "What the overflow does right now"
echo "  Two requests, sent now from ${ATTACKER_IP} to ${SVC_IP}:${SERVICE_PORT}."
echo

service_log_clear
long_reply="$( exploit_send "${waddr:-0}" "$(( ${off:-72} ))" )"
leak=no
grep -qF "$KEY_STRING" <<< "$long_reply" && leak=yes

printf '    %-52s %s\n' "the request that overwrites the return address" \
       "$( [ -n "$long_reply" ] && echo answered || echo "no reply" )"
printf '    %-52s %s\n' "it reaches ${WIN_SYMBOL}() and the key comes back" "$leak"
printf '    %-52s %s\n' "the C library reported a smashed stack" "$( canary_tripped )"

# ---------------------------------------------------------------------------
sec "Does the service still reply to a legitimate request?"
serves="$( service_serves )"
if [ "$serves" = ok ]; then
    printf '    a REGISTER for %s from ops returns "%s"   OK\n' "$LIVE_NAME" "$LIVE_REPLY"
else
    printf '    a REGISTER for %s from ops returns nothing usable       FAIL\n' "$LIVE_NAME"
fi

# ---------------------------------------------------------------------------
sec "The last few lines the service wrote"
service_log_tail 8 | sed 's/^/  /'

# ---------------------------------------------------------------------------
sec "Where the lab stands"

shut=no
[ "$leak" = no ] && shut=yes
mark "$shut"; echo "the exploit is dead: the overflow no longer reaches ${WIN_SYMBOL}()"

works=no
[ "$serves" = ok ] && works=yes
mark "$works"; echo "the service still works: a REGISTER for ${LIVE_NAME} gets its reply"

held=no
[ "$shut" = yes ] && [ "$works" = yes ] && held=yes
mark "$held"; echo "the build holds: both facts at once"

echo
echo "  Read those two lines against the hardening block above them. Most of the"
echo "  builds Part 2 asks for carry hardening that block reports as present"
echo "  while the key still comes back, which is the result the lab is about:"
echo "  a flag defends the mechanism it was designed for and nothing else."
echo "  Working out which of the four changes these two lines is Part 2."
