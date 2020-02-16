#!/bin/sh -x

cd /home/dpavlin/klin/bak-git

if [ ! -z "$1" ] ; then

/usr/sbin/lighttpd -f gitweb/httpd.conf

fi

SSH=autossh ./bak-git-server.pl /home/dpavlin/klin/backup/ '' $*
