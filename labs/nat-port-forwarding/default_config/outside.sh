#!/bin/bash
# Starter configuration for the host beyond the edge.
#
# This machine stands in for everywhere the site is not. It is addressed on the
# outside segment and given the connected route that comes with that address, and
# it is given nothing else: no default route, and no route towards
# 192.168.10.0/24.
#
# That omission is not an oversight to be corrected later in the lab. It is what
# every host on the far side of a NAT looks like, and it is the reason the lab
# exists: a reply addressed to a private destination has nowhere to go, so a
# private client that does not have its source address translated is a client
# whose traffic arrives and whose answers never leave.
set -e

ip addr flush dev 112-ext 2>/dev/null || true
ip addr add 112.0.0.10/24 dev 112-ext
ip link set dev 112-ext up

# The site's public web service, so a private client has something to fetch and
# the fetch leaves a record of the source address this machine saw.
mkdir -p /var/www/localhost/htdocs /var/log/lighttpd
cat > /var/www/localhost/htdocs/index.html <<'HTML'
OUTSIDE-SITE-3D18B4
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

# The mode is set rather than left to the ambient umask: `docker exec` runs with
# umask 0022 under a rootful daemon and 0000 under a rootless one, so a bare
# mkdir gives 755 on one machine and 777 on another.
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
