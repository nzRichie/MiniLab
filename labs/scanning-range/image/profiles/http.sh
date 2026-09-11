#!/bin/sh
# The web service profile, on one drawn port or two.
#
# Two implementations sit behind it and the seed picks one: lighttpd, which is a
# small general-purpose server, or darkhttpd, which is a single static binary
# with no configuration file at all. Both announce themselves and their exact
# release in their own Server header, and that header is what turns "this port
# accepts a connection" into a description of what is behind it. Drawing between
# them is what stops the version half of the scoring being a fact a learner
# memorises after two spawns.
#
# When the seed gave this host the hidden-path item, a directory exists that the
# index does not link to. Directory listing is off in both implementations, so it
# is found by a scanner working through a list of names that are commonly
# present, not by reading the index.
#
# Two decoys can land here. `robots.txt` names a path the server answers 404 for,
# which is a claim about the site that reporting without fetching it costs marks
# for; and a masked banner strips the version out of the Server header, so on
# that host the version has to come from somewhere else or not at all.
set -u
. /etc/minilabs/profiles/_lib.sh

HIDDEN="$( param hidden_path )"
ROBOTS="$( param robots_path )"
MASKED="$( param masked_banner no )"
ACCOUNT="$( param leak_account )"
FILENAME="$( param leak_filename )"
IMPL="$( impl )"
[ -n "$IMPL" ] || IMPL=lighttpd

first=1
for port in $( ports_of_proto tcp ); do
    root="/var/www/lab-${port}"
    mkdir -p "$root"
    cat > "$root/index.html" <<HTML
<!DOCTYPE html>
<html>
<head><title>${ORG_NAME} - service index</title></head>
<body>
<h1>${ORG_NAME}</h1>
<p>Internal service index. Staff only.</p>
<ul>
  <li>Document drop: FTP, elsewhere on this network</li>
  <li>Network equipment: administered over the console</li>
  <li>Sites: $( org_site 1 ), $( org_site 2 ), $( org_site 3 )</li>
</ul>
</body>
</html>
HTML

    # The hidden path goes on the first listener only, so a host with two web
    # ports does not hand the same finding over twice.
    if [ -n "$HIDDEN" ] && [ "$first" -eq 1 ]; then
        mkdir -p "${root}${HIDDEN}"
        cat > "${root}${HIDDEN}index.html" <<HTML
<!DOCTYPE html>
<html>
<head><title>${ORG_NAME} - administration</title></head>
<body>
<h1>Administration console</h1>
<p>This console has not been migrated. Use the document drop for ${ORG_DROP},
and the ${ORG_TEAM} handover notes for anything to do with the switches.</p>
$( [ -n "$ACCOUNT" ] && printf '<p>Standing request from %s: stop sharing the
<code>%s</code> account. Every one of you has your own now.</p>' "$ORG_TEAM" "$ACCOUNT" )
$( [ -n "$FILENAME" ] && printf '<p>Configuration backups are pushed nightly to the
TFTP server as <code>%s</code>. Do not edit them in place.</p>' "$FILENAME" )
</body>
</html>
HTML
    fi

    # A robots.txt that names a path the server does not serve. It is a claim
    # about the site made by the site, and it is wrong, which is the whole point:
    # the finding is what a GET returns, not what a text file asserts.
    if [ -n "$ROBOTS" ] && [ "$first" -eq 1 ]; then
        cat > "$root/robots.txt" <<ROBOTS
User-agent: *
Disallow: ${ROBOTS}
Disallow: /cgi-bin/
ROBOTS
    fi

    case "$IMPL" in
        darkhttpd)
            # No configuration file: every option is an argument, and --daemon is
            # what puts it in the background. Directory listing is off, which is
            # what keeps a path that the index does not link to something a
            # learner has to guess the name of.
            pkill -f "darkhttpd $root" 2>/dev/null
            darkhttpd "$root" --port "$port" --daemon --no-listing >/dev/null 2>&1 \
                || die "darkhttpd failed to start on $port"
            ;;
        *)
            conf="/etc/lighttpd/lab-${port}.conf"
            # mod_dirlisting is loaded and directory listing is left OFF, so a
            # path that the index does not link to is found by guessing its name
            # and not by reading an index of the document root.
            #
            # server.tag replaces the whole Server header when the seed drew the
            # masked banner, which is what a reverse proxy or a hardening guide
            # would have done to this host in the field.
            cat > "$conf" <<CONF
server.document-root = "$root"
server.port          = $port
server.modules       = ( "mod_dirlisting" )
server.pid-file      = "/run/lighttpd-${port}.pid"
index-file.names     = ( "index.html" )
dir-listing.activate = "disable"
mimetype.assign      = ( ".html" => "text/html", ".txt" => "text/plain" )
CONF
            [ "$MASKED" = yes ] && echo 'server.tag = "webserver"' >> "$conf"
            [ -f "/run/lighttpd-${port}.pid" ] && kill "$( cat "/run/lighttpd-${port}.pid" )" 2>/dev/null
            lighttpd -f "$conf" || die "lighttpd failed to start on $port"
            ;;
    esac
    wait_listening tcp "$port" || die "the web service is not listening on $port"

    # The version recorded is the one the service announces about itself, read
    # back off its own Server header rather than from the package database, so
    # what the scorer holds is exactly what a banner grab returns. A masked
    # header carries no digits, version_digits returns nothing, and the scorer
    # awards no version marks for the port rather than marking every learner
    # wrong on it.
    banner="$( curl -sI --max-time 5 "http://127.0.0.1:${port}/" | sed -n 's/^[Ss]erver: *//p' | tr -d '\r' )"
    describe tcp "$port" http "$( version_digits "$banner" )" http www www-http "$IMPL"

    first=0
done

[ -n "$HIDDEN" ] && intel hidden-path
echo "profile http: up (${IMPL})"
