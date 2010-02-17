#!/usr/bin/perl

=head1 bak-git

Simpliest possible backup from remote host (with natcat as
only depenency) to ad-hoc remote server

Install on client with:

  echo install | nc 10.60.0.92 9001 > bak ; chmod 755 bak

=cut

use warnings;
use strict;
use autodie;
use IO::Socket::INET;
use File::Path;

my $dir = shift @ARGV || die "usage: $0 /backup/directory\n";

chdir $dir;
system 'git init' unless -e '.git';

my $server = IO::Socket::INET->new(
	Proto     => 'tcp',
	LocalPort => 9001,
	Listen    => SOMAXCONN,
	Reuse     => 1
) || die $!;

while (my $client = $server->accept()) {
	my ($command,$path,$message) = split(/\s+/,<$client>,3);
	my $ip = $client->peerhost;

	$message ||= '';

	if ( $command eq 'install' ) {
		print $client '#!/bin/sh',$/,'echo $* | nc 10.60.0.92 9001',$/;
		next;
	}

	warn "$ip [$command] $path | $message\n";

	if ( ! -d $ip ) {
		system 'ssh-copy-id', "root\@$ip";
	}


	my $dir = $path;
	$dir =~ s{/[^/]+$}{};

	mkpath "$ip/$dir" unless -e "$ip/$dir";

	if ( $command eq 'add' ) {
		warn 'rsync', "root\@$ip:$path", "$ip/$path";
		system 'rsync', "root\@$ip:$path", "$ip/$path";
		system 'git', 'add', "$ip/$path";
	} else {
		system 'rsync', "root\@$ip:$path", "$ip/$path";
		$message ||= "$command $ip $path";
		system 'git', 'commit', '-m', $message, "$ip/$path";
	}

}

