#!/usr/bin/env python3
"""The collector's decoder, on the outside host that is authoritative for the
operator's zone.

named answers every query under the operator's zone; this reads named's own
query log, picks out the queries whose names carry file data, reassembles the
file, and appends one line per arrival to a record the lab's oracle counts.

Nothing here decides anything and nothing here sends anything. named does the
answering; this only reads what named wrote down. The record is kept HERE, on
the outside, rather than on the workstation the queries came from, because the
question a containment rule answers is not whether the channel tried, it is
whether anything arrived.

A data-carrying name has the fixed shape

    <chunk>.<seq>.<LABEL>.<ZONE>

where <LABEL>.<ZONE> is the fixed suffix this decoder was told to watch (the
handout uses t.evil.lab), <seq> is the chunk's position as a decimal number, and
<chunk> is a run of base32 characters. The file's bytes are the base32 decoding
of the chunks concatenated in <seq> order. base32's alphabet is A-Z and 2-7,
every character of which is a legal DNS label character, so the chunk needs no
further escaping to sit in a name; the padding '=' is dropped on the way out and
restored here.

The source address, the sequence number and the character count go to

    <log>                one line per arrival: epoch src seq chunk nchars

and the running reassembly of each source's file to

    <dir>/<src>.b32      the base32 text, chunks joined in seq order
    <dir>/<src>.bin      its decoding, whose byte length is the headline oracle

Everything -- the suffix to watch, the query-log path, the output paths -- comes
from the command line, because the image holding this script is the same image
every container in the lab runs, including the gateway the learner works from.
"""
import argparse
import base64
import os
import re
import sys
import time

# named's query-log line, whatever the surrounding date format:
#   ... client @0x.. 119.0.0.23#54321 (name): query: <name> IN A ...
# The source is the <ip>#<port> token; the queried name is the token after
# "query:". Taking the name from after "query:" rather than from the
# parenthesised copy avoids the rare line that wraps the parenthesis.
LINE = re.compile(r"client\s+(?:@\S+\s+)?([0-9A-Fa-f:.]+)#\d+.*?query:\s+(\S+)\s+IN\b")


def decode_b32(text):
    """Base32-decode text that may be missing its trailing '=' padding, and may
    be truncated mid-file. Pads to the next 8-character boundary and, on a
    partial reassembly that will not decode whole, falls back to the longest
    prefix that does, so the byte count grows as chunks arrive rather than
    staying at zero until the last one."""
    t = text.upper().encode("ascii", "ignore")
    for end in range(len(t), -1, -8):
        chunk = t[:end]
        if not chunk:
            return b""
        try:
            return base64.b32decode(chunk + b"=" * ((-len(chunk)) % 8))
        except Exception:
            continue
    return b""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suffix", required=True,
                    help="the fixed name suffix data queries end with, e.g. t.evil.lab")
    ap.add_argument("--querylog", required=True, help="named's query-log file to follow")
    ap.add_argument("--log", required=True, help="the per-arrival record to append to")
    ap.add_argument("--dir", required=True, help="where per-source reassemblies are written")
    args = ap.parse_args()

    suffix = "." + args.suffix.rstrip(".").lower()
    os.makedirs(args.dir, exist_ok=True)

    # chunks[src] maps a sequence number to that chunk's base32 text.
    chunks = {}

    def reassemble(src):
        ordered = "".join(chunks[src][i] for i in sorted(chunks[src]))
        with open(os.path.join(args.dir, src + ".b32"), "w") as fh:
            fh.write(ordered)
        data = decode_b32(ordered)
        with open(os.path.join(args.dir, src + ".bin"), "wb") as fh:
            fh.write(data)

    def handle(line):
        m = LINE.search(line)
        if not m:
            return
        src, name = m.group(1), m.group(2).lower().rstrip(".")
        if not name.endswith(suffix):
            return
        head = name[: -len(suffix)]            # "<chunk>.<seq>"
        parts = head.split(".")
        if len(parts) != 2:
            return
        chunk, seq = parts[0], parts[1]
        if not seq.isdigit() or not chunk:
            return
        # Sequence numbers at or above 900 are Status probes: named still logs
        # the query (which is what the reach oracle reads), but the decoder does
        # not fold them into any reassembled file, so running Status never
        # changes a source's byte count.
        if int(seq) >= 900:
            return
        chunks.setdefault(src, {})[int(seq)] = chunk
        with open(args.log, "a") as fh:
            fh.write("%d %s %s %s %d\n" % (int(time.time()), src, seq, chunk, len(chunk)))
            fh.flush()
            os.fsync(fh.fileno())
        reassemble(src)

    # Follow the query log the way `tail -F` does: reopen it if it is truncated
    # or rotated (collector.sh truncates it at spawn), and poll for new lines.
    pos = 0
    while True:
        try:
            with open(args.querylog, "r") as fh:
                fh.seek(0, os.SEEK_END)
                size = fh.tell()
                if size < pos:
                    pos = 0                    # truncated: start over
                fh.seek(pos)
                for line in fh:
                    handle(line)
                pos = fh.tell()
        except FileNotFoundError:
            pass
        time.sleep(0.5)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
