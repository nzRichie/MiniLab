#!/usr/bin/env bash
# Print the lab's state and its own success oracle, so the learner reads what
# changed without shelling into six containers. It reads state and changes
# nothing that the exercise is graded on: the only queries it sends are two
# throwaway probes, one on each transport, whose whole purpose is to report
# whether that transport still reaches the outside.
#
# The oracle is two facts held at once. Containment means BOTH channels are shut
# AND ordinary resolution still works. Either one alone is easy: a gateway that
# forwards nothing shuts every channel and also breaks the resolver, and a
# gateway that forwards everything keeps resolution working and leaks the file.
#
# Every probe it runs comes from lib.sh, so what this prints and what selftest.sh
# asserts cannot drift apart.
set -uo pipefail
source "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

hr()  { printf '%s\n' "------------------------------------------------------------"; }
sec() { echo; hr; echo "$*"; hr; }
mark() { if [ "$1" = yes ]; then printf '  [done] '; else printf '  [    ] '; fi; }

if ! running "$GW_CTN"; then
    echo "The lab is not running ($GW_CTN is not up)."
    echo "Start it with the Spawn action, or scripts/spawn.sh."
    exit 1
fi

sec "Containers"
for ctn in "$GW_CTN" "$RESOLVER_CTN" "$WS1_CTN" "$WS2_CTN" "$PUB_CTN" "$COLLECTOR_CTN" \
           "$SW_IN_CTN" "$SW_OUT_CTN"; do
    if running "$ctn"; then printf '  %-28s up\n' "$ctn"
    else                    printf '  %-28s DOWN\n' "$ctn"; fi
done

# ---------------------------------------------------------------------------
sec "The gateway's egress policy"
rules="$( nft_ruleset )"
if [ -z "$rules" ]; then
    echo "  none. The gateway forwards every packet between the two segments."
else
    echo "$rules" | sed 's/^/  /'
fi

# ---------------------------------------------------------------------------
sec "The resolver's response policy"
if docker exec "$RESOLVER_CTN" sh -c 'grep -q "response-policy {" /etc/bind/rpz-policy.conf 2>/dev/null'; then
    echo "  a response policy is configured. The resolver rewrites the answer for"
    echo "  the names it names, instead of recursing into their zone."
else
    echo "  none. The resolver recurses into every zone it is asked about,"
    echo "  including the operator's."
fi

# ---------------------------------------------------------------------------
sec "Does the file still get out?"
echo "  Two throwaway probes, one on each transport, sent now from ws1:"
echo
direct="$( tunnel_probe_reaches ws1 "$COLLECTOR_IP" )"
viares="$( tunnel_probe_reaches ws1 "$RESOLVER_IP" )"
printf '    straight to the outside on port 53   %s\n' "$direct"
printf '    through the resolver                 %s\n' "$viares"

# ---------------------------------------------------------------------------
sec "Does ordinary resolution still work?"
legit="$( resolves_legit ws2 )"
if [ "$legit" = "$PUB_IP" ]; then
    printf '    www.example.lab from ws2 -> %s   OK\n' "$legit"
else
    printf '    www.example.lab from ws2 -> %s   FAIL\n' "${legit:-no answer}"
fi

# ---------------------------------------------------------------------------
sec "Where the lab stands"

shut=no
if [ "$direct" = blocked ] && [ "$viares" = blocked ]; then shut=yes; fi
mark "$shut"; echo "both transports are blocked: the file cannot get out either way"

works=no
[ "$legit" = "$PUB_IP" ] && works=yes
mark "$works"; echo "ordinary resolution still works: www.example.lab resolves from ws2"

held=no
[ "$shut" = yes ] && [ "$works" = yes ] && held=yes
mark "$held"; echo "the network is contained: both facts hold at once"

echo
echo "  A gateway rule that permits DNS only from the resolver shuts the direct"
echo "  transport but not the one that goes through the resolver. Shutting that"
echo "  one is the resolver's response policy, and it must leave example.lab alone."
