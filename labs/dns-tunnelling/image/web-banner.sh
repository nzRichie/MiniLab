#!/bin/sh
# A one-line web service, the thing the gateway's general-outbound block refuses
# to let an inside host reach. It exists only so that a learner can watch a plain
# HTTP request to the outside be refused while a DNS query is not, which is what
# makes DNS the channel worth blocking. It takes no default text or port: each
# machine names itself.
#
#   web-banner <text> [port]
set -eu
TEXT="${1:?usage: web-banner <text> [port]}"
PORT="${2:-80}"
exec python3 - "$TEXT" "$PORT" <<'PY'
import sys, http.server, socketserver
text, port = sys.argv[1], int(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): return
    def do_GET(self):
        body = (text + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("0.0.0.0", port), H).serve_forever()
PY
