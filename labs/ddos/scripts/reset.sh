#!/usr/bin/env bash
# Return the lab to its clean pre-attack baseline, in place. No teardown.
#
# Five kinds of state accumulate while somebody works through this lab:
#
#   running floods      one python3 per source, each bounded but possibly still
#                       counting down
#   the source's own    the OUTPUT rule each source needs before a SYN flood
#   RST drop            holds any state at all
#   the router          both shapers' counters, the learner's FORWARD rules, and
#                       the per-interface rp_filter and log_martians they set
#   the victim          tcp_syncookies, tcp_max_syn_backlog, the rate-limit
#                       block in BIND, and the statistics dump it appends to
#   the admin           its last four measurements
#
# The floods are killed first, matched on the full path of the tool and never on
# `python3`, which would take the lab's own instruments with it. Then every
# device's starter config is re-applied, which is what restores all of the
# above: re-running the config rather than undoing the learner's edits one at a
# time, because patching a file somebody has already edited is how a reset
# leaves a machine in a state neither the handout nor the answer key describes.
#
# The shapers get their counters back to zero because router.sh deletes and
# re-adds them. `tc qdisc replace` would keep the statistics, and a lab whose
# first reading after a reset is 70000 dropped packets teaches nothing.
set -euo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log() { echo "[reset] $*"; }

running "$ROUTER_CTN" || {
    echo "The lab is not running ($ROUTER_CTN is not up). Spawn it first." >&2
    exit 1
}

# --- stop every flood ------------------------------------------------------
stop_floods
log "stopped any flood still running on the four sources"

# --- re-apply every starter config ----------------------------------------
for d in "${DEVICES[@]}"; do
    ctn="$( ctn_of "$d" )"
    running "$ctn" || { log "$ctn is not running; skipping"; continue; }
    log "re-applying default_config/${d}.sh on $ctn"
    docker cp "$LAB_DIR/default_config/${d}.sh" "$ctn:/home/${d}.sh"
    docker exec "$ctn" chmod 755 "/home/${d}.sh"
    docker exec -i "$ctn" "/home/${d}.sh" >/dev/null
done

# The victim's half-open queue drains on its own timer and a reset cannot hurry
# it: the kernel retransmits each SYN|ACK several times before it gives up on
# the entry, which takes up to a minute. Saying so is better than pretending the
# count is zero when the next command reads it.
sr="$( synrecv )"
if [ "${sr:-0}" -gt 0 ]; then
    log "the victim still holds ${sr} half-open connections; they time out within a minute"
fi

log "reset. Both shapers are back at zero, the router has no policy and no source"
log "check, the victim has syncookies off and no rate limit, and no flood is running."
