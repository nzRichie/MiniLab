#!/usr/bin/env python3
"""The MiniLabs botnet lab controller.

Two roles in one program, told apart by argv:

  c2                     run the controller. Listens for bots on tcp/8080 and
                         for operator commands on a unix socket beside it, keeps
                         the roster and the results, and serves the operator a
                         REPL when it has a terminal.
  c2 -c "<command>"      send one operator command to a controller that is
                         already running, print its reply, and exit. This is
                         what the lab's lifecycle scripts drive it with, and it
                         is the same path the REPL takes.

Operator commands:

  status                 one line per bot: id, address, first seen, last seen,
                         last sequence run, last exit code
  task <shell command>   set the standing task, push it to everyone connected,
                         and replay it to everyone who registers later
  task-once <id> <shell> one bot, no replay
  results [id]           print what came back
  clear                  drop the standing task
  quit                   (REPL only) leave the REPL; the controller keeps running

A command line ending in a backslash continues on the next line, in both the
REPL and `c2 -c`. The handout prints its two long tasks that way so they can be
pasted out of the PDF instead of retyped as one line.

There is no attack command. A flood is a shell command like any other, and this
lab never asks for one.

The roster is a dict keyed by bot id behind one lock, not the list of raw
sockets the COMPX316 demo mutated from two threads. Every change is written
through to disk (the roster as a table, each result as a file) so that
status.sh can report the population without opening this socket, and so that a
controller the learner restarts does not lose what it learned.
"""

import os
import socket
import socketserver
import sys
import threading
import time

# These paths are the controller's half of the contract with scripts/lib.sh.
BOT_PORT = 8080
CTL_SOCK = "/run/minilabs/c2.ctl"
PIDFILE = "/run/minilabs/c2.pid"
STATE_DIR = "/var/lib/c2"
ROSTER = os.path.join(STATE_DIR, "roster.tsv")
RESULTS = os.path.join(STATE_DIR, "results")
TASKFILE = os.path.join(STATE_DIR, "standing-task")
LOGFILE = "/var/log/c2.log"

BOT_MAX = 8                       # guard 5: registrations past this are refused


def log(msg):
    line = "%d %s" % (int(time.time()), msg)
    try:
        with open(LOGFILE, "a") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


class Registry:
    """The population, and the standing task, behind one lock.

    Everything a bot connection thread and the operator command thread both
    touch lives here, and every method that changes it takes the lock and then
    writes the change through to disk before returning. The disk copy is what
    status.sh reads, so it must never lag the in-memory copy across a lock
    boundary.
    """

    def __init__(self):
        self.lock = threading.Lock()
        self.bots = {}            # id -> dict(addr, host, first, last, seq, exit, sock)
        self.task_seq = 0         # 0 means no standing task
        self.task_cmd = None
        os.makedirs(RESULTS, exist_ok=True)
        self._load_task()
        self._load_roster()
        self._write_roster()

    # --- persistence -------------------------------------------------------

    def _load_task(self):
        try:
            with open(TASKFILE) as fh:
                first = fh.readline().split(None, 1)
                self.task_seq = int(first[0])
                self.task_cmd = first[1].rstrip("\n") if len(first) > 1 else None
        except (OSError, ValueError, IndexError):
            self.task_seq, self.task_cmd = 0, None

    def _load_roster(self):
        """Reload the roster a previous controller wrote, marked disconnected.

        A learner is told to kill the controller and watch the population come
        back (question 3), so a restart must not lose who was recruited or when.
        Each reloaded bot keeps its first-seen and its last result, and its
        socket is None until it reconnects, at which point register() refreshes
        it in place rather than assigning a new first-seen. A bot that never
        reconnects lingers in the roster, which is correct: it was recruited,
        and the loader's log still records that it was.
        """
        try:
            with open(ROSTER) as fh:
                for line in fh:
                    f = line.rstrip("\n").split("\t")
                    if len(f) < 7:
                        continue
                    self.bots[f[0]] = dict(
                        id=f[0], addr=f[1], host=f[2],
                        first=int(f[3]), last=int(f[4]), seq=int(f[5]),
                        exit=None if f[6] == "" else int(f[6]), sock=None)
        except (OSError, ValueError):
            pass

    def _write_task(self):
        tmp = TASKFILE + ".tmp"
        with open(tmp, "w") as fh:
            if self.task_cmd is None:
                fh.write("0\n")
            else:
                fh.write("%d %s\n" % (self.task_seq, self.task_cmd))
        os.replace(tmp, TASKFILE)

    def _write_roster(self):
        """Rewrite the roster table. Held under self.lock by every caller.

        One line per bot, tab-separated, in first-seen order so the recruitment
        order a learner is graded on survives:
            id  addr  host  first  last  seq  exit
        """
        rows = sorted(self.bots.values(), key=lambda b: b["first"])
        tmp = ROSTER + ".tmp"
        with open(tmp, "w") as fh:
            for b in rows:
                fh.write("%s\t%s\t%s\t%d\t%d\t%d\t%s\n" % (
                    b["id"], b["addr"], b["host"], b["first"], b["last"],
                    b["seq"], "" if b["exit"] is None else b["exit"]))
        os.replace(tmp, ROSTER)

    # --- bot lifecycle -----------------------------------------------------

    def register(self, ident, addr, host, sock):
        """Add or refresh a bot. Returns the standing task to replay, or None.

        Guard 5 is here: a HELLO from an id not already known is refused once
        the roster holds BOT_MAX distinct bots. A HELLO from a known id is
        always accepted, because it is a reconnection, not growth.
        """
        with self.lock:
            now = int(time.time())
            if ident in self.bots:
                b = self.bots[ident]
                b["last"], b["sock"], b["addr"] = now, sock, addr
                log("reconnect id=%s addr=%s" % (ident, addr))
            else:
                if len(self.bots) >= BOT_MAX:
                    log("refused id=%s addr=%s roster full (%d)"
                        % (ident, addr, BOT_MAX))
                    return "FULL"
                self.bots[ident] = dict(
                    id=ident, addr=addr, host=host, first=now, last=now,
                    seq=0, exit=None, sock=sock)
                log("register id=%s addr=%s host=%s (%d bots)"
                    % (ident, addr, host, len(self.bots)))
            self._write_roster()
            if self.task_cmd is not None:
                return "TASK %d %s" % (self.task_seq, self.task_cmd)
            return None

    def drop(self, ident):
        with self.lock:
            b = self.bots.get(ident)
            if b is not None:
                b["sock"] = None
                self._write_roster()

    def record_result(self, ident, seq, status, body):
        with self.lock:
            b = self.bots.get(ident)
            if b is not None:
                b["seq"], b["exit"], b["last"] = seq, status, int(time.time())
                self._write_roster()
        path = os.path.join(RESULTS, "%s.%d.txt" % (ident, seq))
        with open(path, "wb") as fh:
            fh.write(body)
        log("result id=%s seq=%d exit=%d bytes=%d" % (ident, seq, status, len(body)))

    # --- tasking -----------------------------------------------------------

    def set_task(self, command):
        """Set the standing task, push it to everyone connected, and persist it.

        The push reaches only the sockets that are open now; the persisted copy
        is what register() replays to everyone who arrives later. Both halves
        matter: the push is what makes the bots already installed act at once,
        and the replay is what makes the ones they recruit act without the
        operator touching the keyboard again.
        """
        with self.lock:
            self.task_seq += 1
            self.task_cmd = command
            seq = self.task_seq
            self._write_task()
            targets = [b for b in self.bots.values() if b["sock"] is not None]
        line = ("TASK %d %s\n" % (seq, command)).encode()
        pushed = 0
        for b in targets:
            try:
                b["sock"].sendall(line)
                pushed += 1
            except OSError:
                self.drop(b["id"])
        log("task seq=%d pushed=%d cmd=%s" % (seq, pushed, command))
        return seq, pushed

    def task_once(self, ident, command):
        with self.lock:
            self.task_seq += 1
            seq = self.task_seq
            b = self.bots.get(ident)
            sock = b["sock"] if b else None
        if sock is None:
            return None, 0
        try:
            sock.sendall(("TASK %d %s\n" % (seq, command)).encode())
        except OSError:
            self.drop(ident)
            return seq, 0
        log("task-once id=%s seq=%d cmd=%s" % (ident, seq, command))
        return seq, 1

    def clear_task(self):
        with self.lock:
            self.task_cmd, self.task_seq = None, self.task_seq
            self._write_task()
        log("task cleared")

    # --- operator views ----------------------------------------------------

    def status_text(self):
        with self.lock:
            rows = sorted(self.bots.values(), key=lambda b: b["first"])
            task = (self.task_cmd, self.task_seq)
        lines = []
        if task[0] is None:
            lines.append("standing task: none")
        else:
            lines.append("standing task: seq %d  %s" % (task[1], task[0]))
        lines.append("bots: %d" % len(rows))
        if rows:
            lines.append("%-10s %-12s %-10s %-8s %-8s %-6s %s"
                         % ("id", "address", "host", "first", "last", "seq", "exit"))
            now = int(time.time())
            for b in rows:
                lines.append("%-10s %-12s %-10s %-8s %-8s %-6d %s"
                             % (b["id"], b["addr"], b["host"],
                                "%ds" % (now - b["first"]),
                                "%ds" % (now - b["last"]),
                                b["seq"],
                                "-" if b["exit"] is None else str(b["exit"])))
        return "\n".join(lines)

    def results_text(self, ident=None):
        entries = []
        for name in sorted(os.listdir(RESULTS)):
            if not name.endswith(".txt"):
                continue
            bid = name.split(".", 1)[0]
            if ident and bid != ident:
                continue
            path = os.path.join(RESULTS, name)
            try:
                with open(path, "rb") as fh:
                    body = fh.read()
            except OSError:
                continue
            entries.append((name, body))
        if not entries:
            return "no results yet"
        out = []
        for name, body in entries:
            out.append("=== %s (%d bytes) ===" % (name, len(body)))
            out.append(body.decode(errors="replace").rstrip("\n"))
        return "\n".join(out)


REG = None                        # the one Registry, set in run_controller()


class BotHandler(socketserver.StreamRequestHandler):
    """One thread per bot connection.

    It reads HELLO and RESULT lines and updates the registry. The socket is
    kept in the registry so set_task can push down it; when the read side
    closes, the handler drops the bot's socket reference and returns.
    """

    def handle(self):
        ident = None
        try:
            line = self.rfile.readline()
            if not line:
                return
            parts = line.decode(errors="replace").split()
            if len(parts) < 4 or parts[0].upper() != "HELLO":
                return
            ident, host, addr = parts[1], parts[2], parts[3]
            reply = REG.register(ident, addr, host, self.request)
            if reply == "FULL":
                self.wfile.write(b"FULL\n")
                return
            self.wfile.write((reply + "\n").encode() if reply else b"OK\n")

            while True:
                line = self.rfile.readline()
                if not line:
                    break
                head = line.decode(errors="replace").split()
                if not head or head[0].upper() != "RESULT" or len(head) < 5:
                    continue
                seq, status, nbytes = int(head[2]), int(head[3]), int(head[4])
                body = self.rfile.read(nbytes) if nbytes else b""
                REG.record_result(head[1], seq, status, body)
        except (OSError, ValueError):
            pass
        finally:
            if ident is not None:
                REG.drop(ident)


class ThreadedTCP(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def fold_continuations(text):
    """Join lines that end in a backslash into one command line.

    The operator's transport is one line and cannot become several: the REPL
    reads a line at a time, and the control socket reads one line per
    connection. A task worth setting is longer than a page is wide, so the
    handout prints one broken across several lines with a trailing backslash on
    each, the way a long shell command is written, and this puts it back
    together so it can be pasted rather than retyped.

    A backslash inside the single quotes of `task sh -c '...'` is literal to a
    shell, so this join happens HERE, before any shell sees the command, rather
    than being left to /bin/sh on the bot.

    The backslash is dropped and the two lines are concatenated with nothing
    inserted, so a break has to fall where the text already carries the
    whitespace it needs. Indentation on a continuation line survives into the
    command, which is why the handout only breaks where a run of spaces means
    the same thing as one space.
    """
    out = []
    for line in text.split("\n"):
        if out and out[-1].endswith("\\"):
            out[-1] = out[-1][:-1] + line
        else:
            out.append(line)
    return "\n".join(out)


def handle_operator(cmdline):
    """Run one operator command against the in-process registry, return text."""
    parts = cmdline.split(None, 1)
    verb = parts[0].lower() if parts else ""
    arg = parts[1] if len(parts) > 1 else ""
    if verb == "status":
        return REG.status_text()
    if verb == "task":
        if not arg:
            return "usage: task <shell command>"
        seq, pushed = REG.set_task(arg)
        return "standing task set (seq %d), pushed to %d connected bot(s)" % (seq, pushed)
    if verb == "task-once":
        sub = arg.split(None, 1)
        if len(sub) < 2:
            return "usage: task-once <id> <shell command>"
        seq, pushed = REG.task_once(sub[0], sub[1])
        if seq is None or pushed == 0:
            return "no connected bot with id %s" % sub[0]
        return "task-once sent to %s (seq %d)" % (sub[0], seq)
    if verb == "results":
        return REG.results_text(arg.strip() or None)
    if verb == "clear":
        REG.clear_task()
        return "standing task cleared"
    if verb in ("quit", "exit"):
        return "__quit__"
    return "unknown command: %s" % verb


class CtlHandler(socketserver.StreamRequestHandler):
    """The operator control socket: one command per connection, one reply."""

    def handle(self):
        line = self.rfile.readline().decode(errors="replace").strip()
        if not line:
            return
        out = handle_operator(line)
        if out == "__quit__":
            out = "quit only works in the interactive console (Ctrl-C there stops the controller)"
        self.wfile.write((out + "\n").encode())


class ThreadedUnix(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def run_controller():
    global REG
    os.makedirs(os.path.dirname(PIDFILE), exist_ok=True)
    os.makedirs(STATE_DIR, exist_ok=True)
    REG = Registry()

    bot_srv = ThreadedTCP(("0.0.0.0", BOT_PORT), BotHandler)
    threading.Thread(target=bot_srv.serve_forever, daemon=True).start()

    if os.path.exists(CTL_SOCK):
        os.unlink(CTL_SOCK)
    ctl_srv = ThreadedUnix(CTL_SOCK, CtlHandler)
    os.chmod(CTL_SOCK, 0o666)
    threading.Thread(target=ctl_srv.serve_forever, daemon=True).start()

    with open(PIDFILE, "w") as fh:
        fh.write("%d\n" % os.getpid())
    log("controller up on tcp/%d, control socket %s" % (BOT_PORT, CTL_SOCK))

    # A clean stop: drop the control socket and the pid file so status.sh
    # reports the controller as not running once this process is gone. The
    # bot-facing and control servers are daemon threads, so they end when this
    # function returns and the process exits.
    def shutdown():
        for path in (CTL_SOCK, PIDFILE):
            try:
                os.unlink(path)
            except OSError:
                pass
        log("controller stopped")

    banner = ("MiniLabs controller. Bots check in on tcp/%d.\n"
              "Commands: status | task <cmd> | task-once <id> <cmd> | "
              "results [id] | clear | quit\n"
              "Ctrl-C or quit stops the controller. The bots keep running and\n"
              "reconnect when you start it again.\n" % BOT_PORT)
    if sys.stdin.isatty():
        sys.stdout.write(banner)
        # Ctrl-C and quit both stop the controller and exit: there is no
        # detached background mode, because a controller that "keeps running"
        # after Ctrl-C would contradict the reconnect exercise, where stopping
        # it is the whole point. A second Ctrl-C during shutdown is swallowed
        # rather than printing a traceback.
        try:
            while True:
                sys.stdout.write("c2> ")
                sys.stdout.flush()
                line = sys.stdin.readline()
                if not line:          # Ctrl-D
                    break
                line = line.rstrip("\n")
                # A trailing backslash means the command continues on the next
                # line, so a long task can be pasted out of the handout in the
                # shape it is printed in. The prompt changes to say the
                # controller is still reading one command.
                while line.endswith("\\"):
                    sys.stdout.write("...> ")
                    sys.stdout.flush()
                    more = sys.stdin.readline()
                    if not more:      # Ctrl-D mid-command: drop it
                        line = ""
                        break
                    line = line[:-1] + more.rstrip("\n")
                line = line.strip()
                if not line:
                    continue
                out = handle_operator(line)
                if out == "__quit__":
                    break
                sys.stdout.write(out + "\n")
        except KeyboardInterrupt:
            pass
        sys.stdout.write("\nstopping the controller.\n")
        shutdown()
        return
    else:
        # No terminal (spawned by a script): serve until signalled.
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            pass
        shutdown()


def send_command(cmdline):
    """The `c2 -c` path: connect to a running controller and print its reply."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(CTL_SOCK)
    except OSError:
        sys.stderr.write("no controller is running (control socket %s absent).\n"
                         % CTL_SOCK)
        sys.exit(1)
    cmdline = fold_continuations(cmdline)
    sock.sendall((cmdline + "\n").encode())
    sock.shutdown(socket.SHUT_WR)
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    sys.stdout.write(data.decode(errors="replace"))


def main():
    argv = sys.argv[1:]
    if argv and argv[0] == "-c":
        if len(argv) < 2:
            sys.stderr.write("usage: c2 -c \"<command>\"\n")
            sys.exit(2)
        send_command(argv[1])
        return
    run_controller()


if __name__ == "__main__":
    main()
