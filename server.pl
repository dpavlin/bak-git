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
	my ($pwd,$command,$path,$message) = split(/\s+/,<$client>,4);
	my $ip = $client->peerhost;

	$message ||= '';
	$path = "$pwd/$path" unless $path =~ m{^/};

	if ( $command eq 'install' ) {
		print $client '#!/bin/sh',$/,'echo `pwd` $* | nc 10.60.0.92 9001',$/;
		next;
	}

	warn "$ip [$command] $path | $message\n";

	if ( ! -d $ip ) {
		system 'ssh-copy-id', "root\@$ip";
	}


	my $dir = $path;
	$dir =~ s{/[^/]+$}{};

	mkpath "$ip/$dir" unless -e "$ip/$dir";

	if ( ! $command ) {
		system "find $ip -type f | sed 's,$ip,,' > /tmp/$ip.list";
		system "rsync -avv --files-from /tmp/$ip.list root\@$ip:/ $ip/"
	} elsif ( $command eq 'add' ) {
		system 'rsync', '-avv', "root\@$ip:$path", "$ip/$path";
		system 'git', 'add', "$ip/$path";
	} elsif ( $command eq 'commit' ) {
		system 'rsync', '-avv', "root\@$ip:$path", "$ip/$path";
		$message ||= "$command $ip $path";
		system 'git', 'commit', '-m', $message, "$ip/$path";
	} elsif ( $command =~ m{(diff|status|log)} ) {
		print $client `git $command $ip`;
	} else {
		print $client "Unknown command: $command\n";
	}

}

