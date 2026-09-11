#!/usr/bin/env bash
# Tear the range down and spawn a fresh one at the same tier.
#
#   scripts/regenerate.sh [seed]
#
# Reset to baseline has no meaning on a range: there is no configuration the
# learner wrote to roll back, and re-applying the starter state would hand back
# the same network with the same answers. Regenerate replaces it, and the learner
# replays the range as often as they like on a different network each time.
#
# The tier is read from the range that is up, so a learner who chose `hard` stays
# on `hard` without being asked again. Passing a seed reproduces a specific range
# at that tier, which is how a tutor hands one out.
set -euo pipefail
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$HERE/lib.sh"

seed="${1:-}"

if [ ! -f "$TOPO_ENV" ]; then
    echo "No range has been generated yet. Use Spawn and pick a tier." >&2
    exit 1
fi
tier="$( sed -n 's/^RANGE_TIER=//p' "$TOPO_ENV" )"
case "$tier" in
    easy|normal|hard) ;;
    *) echo "cannot read a tier out of $TOPO_ENV" >&2; exit 1 ;;
esac

echo "[regenerate] tearing down the range that is up"
"$HERE/teardown.sh"
echo "[regenerate] spawning a fresh range at tier $tier"
exec "$HERE/spawn.sh" "$tier" $seed
