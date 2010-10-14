#!/bin/sh -x

/usr/sbin/lighttpd -f gitweb/httpd.conf
./bak-git-server.pl /home/dpavlin/klin/backup/ 10.60.0.92 $*
