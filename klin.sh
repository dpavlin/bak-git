 #!/bin/sh -x

if [ -z "$1" ] ; then

/usr/sbin/lighttpd -f gitweb/httpd.conf

autossh -N -R 9001:10.60.0.92:9001 root@webgui &
autossh -N -R 9001:10.60.0.92:9001 root@saturn.ffzg.hr &
autossh -N asa-klin &

fi

./bak-git-server.pl /home/dpavlin/klin/backup/ 10.60.0.92 $*
