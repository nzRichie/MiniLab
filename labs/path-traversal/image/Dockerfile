# Host image for the path traversal and credential reuse lab.
#
# One image serves every role on top of the stock mini-internet host image:
#   * web       the customer portal: lighttpd running view.php over CGI, and the
#               only host the traversal reaches any file on
#   * db        MariaDB, and the machine stages 2C and 2D are worked on
#   * reports   the nightly report job; the second tier that connects to the
#               database with the same account the portal uses
#   * attacker  the machine every request is sent from, and the machine the
#               direct login at the end of Part 1 is attempted from
#
# The vulnerable program is PHP and is not compiled. The artifact the handout
# quotes is one line of source, so there are no build-specific offsets to pin;
# the source is still baked in here rather than downloaded, and
# default_config/web.sh reinstalls it from the pristine copy on every spawn and
# every reset, so a learner who edited it gets the original back.
FROM miniinterneteth/d_host:latest

# lighttpd serves the viewer; php82-cgi is the interpreter mod_cgi hands a .php
# file to, and php82-mysqli is the extension the viewer looks a document title
# up with. mod_access is built into this lighttpd and needs no package, but it
# is not loaded unless server.modules names it, which is what Part 2A does.
#
# mariadb is the server the db container runs; mariadb-client is the tool
# default_config/db.sh loads the schema with, the tool the nightly report job
# runs, and the tool the attacker attempts the direct login with, so both
# packages are in the one image.
#
# curl is how every request in this lab is sent. iproute2 gives a full `ip`,
# whose `ip -o` output the lifecycle scripts parse; the base image's /sbin/ip is
# BusyBox's applet.
RUN apk add --no-cache \
        lighttpd php82 php82-cgi php82-mysqli \
        mariadb mariadb-client mariadb-common \
        curl iproute2

# The pristine copies. default_config installs from here on every spawn and
# every reset.
#
# php.ini is copied to a pristine path as well, because Part 2B edits the live
# one and a reset has to be able to put the packaged file back. Copying the
# packaged file at build time is what makes that possible without this lab
# shipping a php.ini of its own that would go stale against the package.
RUN mkdir -p /usr/local/lib/minilabs /usr/local/lib/minilabs/docs /etc/minilabs /srv/docs \
    && cp /etc/php82/php.ini /usr/local/lib/minilabs/php.ini
COPY view.php       /usr/local/lib/minilabs/view.php
COPY schema.sql     /usr/local/lib/minilabs/schema.sql
COPY nightly-report /usr/local/bin/nightly-report
COPY docs/          /usr/local/lib/minilabs/docs/

# Every mode is set explicitly rather than left to the ambient umask: docker
# exec runs with umask 0022 under a rootful daemon and 0000 under a rootless
# one, so a bare mkdir yields 755 on one and 777 on the other.
#
# /run/mysqld is created here because mariadbd opens its unix socket there
# before it would create the directory itself, and /var/log/lighttpd because
# lighttpd opens its error log before it serves anything and refuses to start
# if the directory is missing.
RUN chmod 644 /usr/local/lib/minilabs/view.php \
              /usr/local/lib/minilabs/schema.sql \
              /usr/local/lib/minilabs/php.ini \
    && chmod 644 /usr/local/lib/minilabs/docs/* \
    && chmod 755 /usr/local/bin/nightly-report \
    && mkdir -p /run/mysqld /var/lib/mysql /var/log/lighttpd /var/www/html /etc/mysql \
    && chown mysql:mysql /run/mysqld /var/lib/mysql \
    && chmod 755 /run/mysqld /var/lib/mysql /var/log/lighttpd /var/www /var/www/html \
                 /etc/mysql /etc/minilabs /srv/docs /usr/local/lib/minilabs
