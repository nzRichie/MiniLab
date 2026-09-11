#!/bin/sh
# Shared helpers for the service profiles. Sourced by each profile script; no
# side effects beyond creating the directories the descriptors live in.
#
# A profile script does three things, in this order:
#   1. start its service on the ports it was given;
#   2. confirm the service is listening;
#   3. only then write the descriptor score.sh reads back.
#
# That order is the whole point of keeping ground truth in the container. A
# profile that failed to start writes no descriptor, so it scores as a port that
# is not open rather than as a finding the learner missed, and a broken range
# marks a learner down for nothing it never had to.
#
# A HOST RUNS MORE THAN ONE PROFILE. spawn.sh writes profile.env and runs one
# profile script, then rewrites it and runs the next, so a host drawn with a web
# service, an SNMP agent and six junk listeners is three invocations of this file
# and three sets of descriptors. Nothing here may therefore clear state a
# previous profile on the same host wrote, which is why the intel file is created
# and not truncated.

PROFILE_D=/etc/minilabs/profile.d
INTEL_FILE=/etc/minilabs/intel
mkdir -p "$PROFILE_D"
[ -f "$INTEL_FILE" ] || : > "$INTEL_FILE"

# Parameters the seed drew for this host, written by spawn.sh.
[ -f /etc/minilabs/profile.env ] && . /etc/minilabs/profile.env

# param <name> [default] -- one drawn parameter, from the space-separated
# key=value list in PROFILE_PARAM.
param() {
    _want="$1"; _def="${2:-}"
    for _kv in ${PROFILE_PARAM:-}; do
        case "$_kv" in "$_want"=*) echo "${_kv#*=}"; return ;; esac
    done
    echo "$_def"
}

# The implementation drawn for this profile, where the class has two. Empty for
# a class with only one, and every profile that has two treats the empty case as
# its first implementation rather than failing, so a range generated before an
# implementation was added still spawns.
impl() { echo "${PROFILE_IMPL:-}"; }

# The ports drawn for THIS profile, as "tcp/80 udp/53" specs. Not the host's
# ports: a host running three profiles gets three different lists.
ports_of_proto() {   # <tcp|udp>
    for _spec in ${PROFILE_PORTS:-}; do
        case "$_spec" in "$1"/*) echo "${_spec#*/}" ;; esac
    done
}

# The first TCP port drawn for this profile, which is what a single-listener
# service wants.
first_tcp() { ports_of_proto tcp | head -1; }
first_udp() { ports_of_proto udp | head -1; }

# Wait until something is bound to <proto>/<port> inside this container.
wait_listening() {   # <tcp|udp> <port> [tries]
    _flag=-tln; [ "$1" = udp ] && _flag=-uln
    _tries="${3:-40}"
    while [ "$_tries" -gt 0 ]; do
        if netstat "$_flag" 2>/dev/null | grep -qE "[:.]$2 +"; then return 0; fi
        _tries=$(( _tries - 1 )); sleep 0.25
    done
    return 1
}

# Record one open port. This is the file score.sh recovers ground truth from, so
# it is written only after wait_listening has succeeded.
#
#   describe <proto> <port> <service> <version> <accept...>
#
# `accept` is the list of service names a learner may submit for the port and be
# marked correct, which is what keeps a synonym table out of the scorer. An empty
# version means the service announces none, and the scorer awards no version
# marks for such a port rather than marking every learner wrong on it.
describe() {
    _proto="$1"; _port="$2"; _service="$3"; _version="$4"; shift 4
    {
        echo "service=$_service"
        echo "version=$_version"
        echo "accept=$*"
    } > "$PROFILE_D/${_proto}-${_port}"
}

# Record one intel item. The token must be one of the ones lib.sh lists and the
# field manual prints.
intel() { echo "$1" >> "$INTEL_FILE"; }

# The first digit-and-dot run in a string, which is how both this file and
# score.sh reduce a banner to a version number.
version_digits() { echo "$1" | grep -oE '[0-9]+(\.[0-9]+)*' | head -1; }

# The organisation this range belongs to, and the machine's own place in it.
# Everything a learner reads while enumerating is templated from these, so a
# handover note found on the second spawn is not the one they skimmed on the
# first.
ORG_NAME="${ORG_NAME:-Kiwi Freight Ltd}"
ORG_ZONE="${ORG_ZONE:-range.lab}"
ORG_PREFIX="${ORG_PREFIX:-kfl}"
ORG_TEAM="${ORG_TEAM:-network operations}"
ORG_SITES="${ORG_SITES:-Auckland Tauranga Christchurch}"
ORG_DROP="${ORG_DROP:-freight manifests}"
HOST_CLASS="${HOST_CLASS:-server}"

# The three sites, one per line, for a schedule or an inventory.
org_site() {   # <1|2|3>
    echo "$ORG_SITES" | tr ' ' '\n' | sed -n "${1}p"
}

die() { echo "profile: $*" >&2; exit 1; }
