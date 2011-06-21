#!/bin/sh -x

if [ -z "$1" ] ; then

/usr/sbin/lighttpd -f gitweb/httpd.conf

fi

SSH=autossh ./bak-git-server.pl /home/dpavlin/klin/backup/ 10.60.0.92 $*
