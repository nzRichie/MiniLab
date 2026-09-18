#!/usr/bin/env bash
# The one copy of the privileged wiring helper, sourced by every lab's lib.sh and
# by every sandbox create mode generates. Sourcing it has no side effects: it
# defines three functions and assigns nothing.
#
# A lab sits at labs/catalogue/<lab>/scripts/ in the source tree and at
# labs/<lab>/scripts/ in a release, so no fixed relative path reaches this file
# from both. Each caller walks up from ${BASH_SOURCE[0]} to the first ancestor
# holding lib/helper.sh and sources that.
#
# Inputs, set by the caller before the first call:
#
#   HELPER_CTN          required. The helper container's name. The caller builds
#                       it however it likes; this file does not care.
#   HELPER_IMAGE        the image to run. Defaults to $HOST_IMAGE.
#   HELPER_INIT         1 runs the helper with --init. ospf-routing needs it:
#                       FRR's daemons leave zombies behind without a reaper.
#   HELPER_TTL          the `sleep` bound in seconds. Default 600.
#   HELPER_READY_TRIES  readiness polls at 0.25s each. Default 40.
#   HELPER_LABEL        `key=value` to put on the helper container. A create-mode
#                       sandbox sets it, because its teardown removes by label
#                       and an unlabelled helper is one teardown would leave
#                       running. Catalogue labs leave it unset and remove the
#                       helper by name.
#
# Exports: helper_start, helper, helper_stop.
#
# ---------------------------------------------------------------------------
# Why the helper looks like this.
#
# Wiring a lab needs privileges a learner's account will not have: CAP_NET_ADMIN
# to create a veth pair, and CAP_SYS_ADMIN to enter a container's network
# namespace and rename the interface inside it. Rather than require root on the
# host, a throwaway --privileged container holds them.
#
# The helper keeps a network namespace of its own (--network=none). Both ends of
# every veth pair are moved out into lab containers, so the namespace the pair is
# created in never matters. Asking for the host's namespace (--network=host)
# only breaks the helper under a rootless daemon, where that namespace belongs to
# a user namespace the helper holds no privilege in and every `ip link add`
# returns EPERM. --pid=host stays: it is what makes each lab container's
# /proc/<pid>/ns/net reachable for the moves.
#
# Renames run through `nsenter --net`, not `ip netns exec`. iproute2 remounts
# /sys on every namespace switch and a user namespace forbids that, while the
# rename itself is pure netlink and needs no sysfs at all.
#
# The kernel objects are identical to the host-root path: same veth pair, same
# namespaces, same interface names, same OVS ports. Only the identity of the
# process issuing the netlink calls changes, which nothing in the data plane can
# observe. Docker access is the only privilege a learner needs, and on a rootless
# daemon that access no longer carries root on the host.
#
# Four invariants hold wherever this file is used, and each one was a lab that
# would not boot:
#
#   - never `--network=host` on the helper;
#   - `nsenter --net=/proc/<pid>/ns/net`, never `ip netns exec` or `ip -n`;
#   - no bare `ip link` outside the helper, and no writes to /run/netns;
#   - Open vSwitch starts with `ovs-ctl start --no-mlockall`, not the image's
#     supervisord entrypoint, because --mlockall cannot exceed RLIMIT_MEMLOCK in
#     a user namespace and ovs-vswitchd dies on pthread_create.

# Start the helper and wait until it accepts commands. Idempotent: any helper
# left over from an interrupted spawn is removed first. `--rm` plus a bounded
# sleep means an interrupted spawn cannot leave one running forever; callers also
# stop it explicitly through an EXIT trap.
helper_start() {
    local image="${HELPER_IMAGE:-$HOST_IMAGE}"
    local ttl="${HELPER_TTL:-600}"
    local tries="${HELPER_READY_TRIES:-40}"
    local init_arg=()
    local label_arg=()

    if [ -z "${HELPER_CTN:-}" ]; then
        echo "helper_start: HELPER_CTN is not set" >&2
        return 1
    fi
    if [ -z "$image" ]; then
        echo "helper_start: neither HELPER_IMAGE nor HOST_IMAGE is set" >&2
        return 1
    fi
    [ "${HELPER_INIT:-}" = "1" ] && init_arg=(--init)
    [ -n "${HELPER_LABEL:-}" ] && label_arg=(--label "$HELPER_LABEL")

    docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true
    docker run -d --rm "${init_arg[@]}" "${label_arg[@]}" --name "$HELPER_CTN" \
        --privileged --network=none --pid=host \
        "$image" sleep "$ttl" >/dev/null

    for _ in $(seq 1 "$tries"); do
        if docker exec "$HELPER_CTN" true >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    echo "helper container $HELPER_CTN did not become ready" >&2
    return 1
}

# Run one privileged networking command inside the helper.
helper() { docker exec "$HELPER_CTN" "$@"; }

helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }
