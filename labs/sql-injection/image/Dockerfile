# Host image for the SQL injection and least-privilege lab.
#
# One image serves every role on top of the stock mini-internet host image:
#   * web       the storefront: lighttpd running the two PHP endpoints over CGI
#   * db        MariaDB, and the machine every stage of Part 2 is worked on
#   * attacker  the machine the requests are sent from, and the machine the
#               direct login at the end of Part 1 is attempted from
#
# The vulnerable program is not compiled. The other labs in this category build
# their binary here because the offsets their handout quotes are facts about
# that exact build; a SQL injection has no offsets, and the artifact this
# handout quotes is the one line of PHP that pastes a query parameter into the
# statement text. The source is still baked in rather than downloaded, and
# default_config/web.sh reinstalls it from the pristine copy on every spawn and
# every reset, so a learner who edited it gets the original back.
FROM miniinterneteth/d_host:latest

# lighttpd serves the two endpoints; php82-cgi is the interpreter mod_cgi hands
# a .php file to, and php82-mysqli is the extension the endpoints connect with.
#
# mariadb is the server the db container runs and mariadb-client is both the
# tool default_config/db.sh loads the schema with and the tool the attacker
# attempts the direct login with, so both packages are in the one image.
#
# curl is how every request in this lab is sent: --data-urlencode is what lets a
# payload carry a quote, a space and a comment marker without hand-writing
# percent escapes. The base image has no curl.
#
# iproute2 gives a full `ip`, whose `ip -o` output the lifecycle scripts parse;
# the base image's /sbin/ip is BusyBox's applet. nftables is where Part 2C's
# rule is written.
RUN apk add --no-cache \
        lighttpd php82 php82-cgi php82-mysqli \
        mariadb mariadb-client mariadb-common \
        curl iproute2 nftables

# The pristine copies of the two endpoints and the schema. default_config
# installs from here on every spawn and every reset.
RUN mkdir -p /usr/local/lib/minilabs /etc/minilabs
COPY search.php /usr/local/lib/minilabs/search.php
COPY stock.php  /usr/local/lib/minilabs/stock.php
COPY schema.sql /usr/local/lib/minilabs/schema.sql

# Every mode is set explicitly rather than left to the ambient umask: docker
# exec runs with umask 0022 under a rootful daemon and 0000 under a rootless
# one, so a bare mkdir yields 755 on one and 777 on the other.
#
# /run/mysqld is created here because mariadbd opens its unix socket there
# before it would create the directory itself, and /var/log/lighttpd because
# lighttpd opens its error log before it serves anything and refuses to start
# if the directory is missing.
RUN chmod 644 /usr/local/lib/minilabs/search.php \
              /usr/local/lib/minilabs/stock.php \
              /usr/local/lib/minilabs/schema.sql \
    && mkdir -p /run/mysqld /var/lib/mysql /var/log/lighttpd /var/www/html /etc/mysql \
    && chown mysql:mysql /run/mysqld /var/lib/mysql \
    && chmod 755 /run/mysqld /var/lib/mysql /var/log/lighttpd /var/www /var/www/html /etc/mysql \
    && chmod 755 /etc/minilabs
