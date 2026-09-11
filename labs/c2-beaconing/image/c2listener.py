#!/usr/bin/env python3
"""The controller's listener, on ext2.

It accepts a check-in on a plain HTTP port and on a TLS port at the same time,
appends one line per arrival to a log file, and replies with a body of a fixed
length. Nothing here decides anything: the implant chooses which port to use and
when, and this only records what arrived.

The log is the lab's headline oracle, and it is deliberately kept HERE rather
than on the workstation that sends the check-ins. A containment rule is not
graded on whether the implant tried; it is graded on whether anything arrived.

One line per arrival, space separated so `awk` can read it without a JSON tool:

    <epoch seconds> <source address> <port it arrived on> <request body bytes>

No address, port, interval or path is written into this file. Everything comes
from the command line, because the image holding this script is the same image
every container in the lab runs, including the gateway the learner works from.
"""

import argparse
import http.server
import os
import socketserver
import ssl
import sys
import threading
import time


class CheckInHandler(http.server.BaseHTTPRequestHandler):
    # HTTP/1.1 rather than the BaseHTTPRequestHandler default of 1.0, so a
    # Content-Length reply keeps the connection open the way a real service
    # would. A check-in that had to open a fresh connection every time would be
    # a stronger signal than this lab intends to hand over.
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        """Silence the default stderr line; the log file below is the record."""
        return

    def _record(self, nbytes):
        line = "%d %s %d %d\n" % (
            time.time(),
            self.client_address[0],
            self.server.server_address[1],
            nbytes,
        )
        # Opened and closed per arrival rather than held open, so a reader that
        # runs between check-ins sees a complete file and never a partial line.
        with open(self.server.checkin_log, "a") as fh:
            fh.write(line)
            fh.flush()
            os.fsync(fh.fileno())

    def _reply(self):
        """Every reply is the same length, which is one of the things the lab
        asks the learner to measure. A controller's answer to a check-in is a
        task, and a task list that is empty most of the time is the same few
        bytes every time."""
        body = self.server.reply_body
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        try:
            n = int(self.headers.get("Content-Length", 0))
        except ValueError:
            n = 0
        if n:
            self.rfile.read(n)
        self._record(n)
        self._reply()

    def do_GET(self):
        self._record(0)
        self._reply()


class Listener(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def serve(port, log_path, reply_bytes, cert=None):
    srv = Listener(("0.0.0.0", port), CheckInHandler)
    srv.checkin_log = log_path
    # A fixed body rather than random bytes: the length is the point, and a
    # length that varied would make the lab's own claim about it false.
    srv.reply_body = (b"T" * reply_bytes)[:reply_bytes]
    if cert:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert)
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    srv.serve_forever()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--http-port", type=int, required=True)
    ap.add_argument("--tls-port", type=int, required=True)
    ap.add_argument("--cert", required=True, help="PEM holding the certificate and its key")
    ap.add_argument("--log", required=True)
    ap.add_argument("--reply-bytes", type=int, required=True)
    args = ap.parse_args()

    open(args.log, "a").close()

    t = threading.Thread(
        target=serve,
        args=(args.http_port, args.log, args.reply_bytes),
        daemon=True,
    )
    t.start()

    # The TLS listener runs in the main thread, so a certificate this process
    # cannot load is a startup failure with a message rather than a listener
    # that silently never came up.
    try:
        serve(args.tls_port, args.log, args.reply_bytes, cert=args.cert)
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
