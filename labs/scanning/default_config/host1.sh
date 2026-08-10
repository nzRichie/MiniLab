#!/bin/bash
# host1: the HTTP service, at 104.1.0.23. This file is named for the container
# rather than for the service it starts, because `docker ps` and spawn.sh's log
# lines are things a learner sees before they have scanned anything.
#
# An ordinary small web server, not a misconfigured one: it serves a couple of
# pages over port 80 and identifies itself in its own Server header, which is
# exactly what a real one does.
#
# What the learner gets from it is identification, not a way in. The banner names
# the software and its exact version, the page title names the organisation, and
# an /admin/ path exists to be found by a script that guesses common directory
# names. Those three facts are what turn "port 80 is open" into a description of
# what is running.
set -e

ip address add 104.1.0.23/24 dev 104-S1 2>/dev/null || true
ip link set 104-S1 up
ip route add default via 104.1.0.1 2>/dev/null || true

DOCROOT=/var/www/localhost/htdocs
mkdir -p "$DOCROOT/admin"

cat > "$DOCROOT/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Kiwi Freight Ltd - Internal Services</title></head>
<body>
<h1>Kiwi Freight Ltd</h1>
<p>Internal services index. Staff only.</p>
<ul>
  <li><a href="/admin/">Administration console</a></li>
  <li>Document drop: FTP, elsewhere on this network</li>
  <li>Network equipment: managed over the console, see network operations</li>
</ul>
</body>
</html>
EOF

cat > "$DOCROOT/admin/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Kiwi Freight Ltd - Administration console</title></head>
<body>
<h1>Administration console</h1>
<p>This console has not been migrated yet. Use the document drop for manifests
and the network operations handover notes for anything to do with the switches.</p>
</body>
</html>
EOF

# mod_dirlisting is loaded but directory listing is left off, so /admin/ is found
# only by a scanner that guesses the name rather than by reading an index of the
# document root.
cat > /etc/lighttpd/lighttpd-lab.conf <<'EOF'
server.document-root = "/var/www/localhost/htdocs"
server.port          = 80
server.modules       = ( "mod_dirlisting" )
server.pid-file      = "/run/lighttpd-lab.pid"
index-file.names     = ( "index.html" )
dir-listing.activate = "disable"
mimetype.assign      = ( ".html" => "text/html", ".txt" => "text/plain" )
EOF

# Restart cleanly so a reset always comes up with a fresh listener.
pkill -x lighttpd 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -x lighttpd >/dev/null 2>&1 || break; sleep 0.2; done
lighttpd -f /etc/lighttpd/lighttpd-lab.conf || { echo "lighttpd failed to start" >&2; exit 1; }
# What this prints is streamed into the TUI's Spawn panel, so it names no
# address, port, service or account: the learner reads this before they have
# scanned anything, and all of that is what Parts 1 to 3 have them find.
echo "host1 configured"
