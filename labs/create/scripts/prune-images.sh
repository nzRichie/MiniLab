#!/usr/bin/env bash
# Remove the images sandboxes built.
#
# Sandbox images are content-hashed, so editing a preset leaves the old image
# behind rather than replacing it. Over a term of drawing and redrawing that
# adds up, and nothing else ever collects them.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

need_docker

mapfile -t images < <( docker images --filter 'reference=minilabs-sandbox-*' \
                       --format '{{.Repository}}:{{.Tag}}' | sort )

if [ ${#images[@]} -eq 0 ]; then
    log "no sandbox images on this machine."
    exit 0
fi

log "${#images[@]} sandbox image(s):"
printf '    %s\n' "${images[@]}"
echo

removed=0 kept=0
for i in "${images[@]}"; do
    # An image a running container is using is refused by the daemon, which is
    # the right answer: it prints why and moves on rather than tearing something
    # out from under a spawned sandbox.
    if err="$( docker rmi "$i" 2>&1 >/dev/null )"; then
        echo "  removed $i"
        removed=$(( removed + 1 ))
    else
        echo "  kept    $i"
        echo "          $( echo "$err" | head -1 )"
        kept=$(( kept + 1 ))
    fi
done

echo
log "$removed removed, $kept kept."
[ "$kept" -gt 0 ] && log "the kept ones are in use; tear down the sandbox using them first."
exit 0
