#!/bin/bash
# Starter configuration for the private segment's web service.
#
# It is addressed out of the private prefix and given a default route through the
# edge router, like every other machine on its segment. It serves its marker on
# port 80 and it is reachable from the two private clients the moment the lab
# spawns; nothing outside the site can reach it until the learner writes a
# destination NAT rule in Part 4.
set -e

ip addr flush dev 112-S1 2>/dev/null || true
ip addr add 192.168.10.20/24 dev 112-S1
ip link set dev 112-S1 up
ip route replace default via 192.168.10.1

mkdir -p /var/www/localhost/htdocs /var/log/lighttpd
cat > /var/www/localhost/htdocs/index.html <<'HTML'
INSIDE-SITE-9C40FA
HTML
chmod 644 /var/www/localhost/htdocs/index.html

# The endpoint the whole lab is read through. It prints the source address of the
# connection lighttpd is answering, so a client learns in one command what
# address this machine saw it as. That is the single fact every translation in
# the lab changes, and putting it in the response body rather than in a log file
# means the client reads it directly: no second shell, and no waiting on
# lighttpd's access-log buffer, which is flushed on a timer and can be a second
# behind the request that filled it.
cat > /var/www/localhost/htdocs/whoami.cgi <<'CGI'
#!/bin/sh
printf 'Content-Type: text/plain\r\n\r\n%s\n' "$REMOTE_ADDR"
CGI
chmod 755 /var/www/localhost/htdocs/whoami.cgi
chmod 755 /var/www/localhost/htdocs /var/log/lighttpd

cat > /etc/lighttpd/lighttpd.conf <<'CONF'
server.document-root = "/var/www/localhost/htdocs"
server.port          = 80
server.pid-file      = "/run/lighttpd.pid"
server.errorlog      = "/var/log/lighttpd/error.log"
server.modules       = ( "mod_accesslog", "mod_indexfile", "mod_cgi" )
index-file.names     = ( "index.html" )
mimetype.assign      = ( ".html" => "text/html" )
accesslog.filename   = "/var/log/lighttpd/access.log"
cgi.assign           = ( ".cgi" => "" )
CONF

pkill -x lighttpd 2>/dev/null || true
sleep 0.3
: > /var/log/lighttpd/access.log
lighttpd -f /etc/lighttpd/lighttpd.conf
