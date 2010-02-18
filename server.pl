#!/usr/bin/perl

=head1 bak-git

Simpliest possible backup from remote host (with natcat as
only depenency) to ad-hoc remote server

Install on client with:

  echo install | nc 127.0.0.1 9001 > bak ; chmod 755 bak

Start server with:

  ./server.pl /path/to/backup 127.0.0.1

You will want to add following to C<~/.ssh/config>

  RemoteForward 9001 localhost:9001

=cut

use warnings;
use strict;
use autodie;
use IO::Socket::INET;
use File::Path;

my ( $dir, $server_ip ) = @ARGV;
die "usage: $0 /backup/directory\n" unless $dir;
$server_ip ||= '127.0.0.1';

my $shell_client = <<__SHELL_CLIENT__;
#!/bin/sh
echo `pwd` \$* | nc $server_ip 9001
__SHELL_CLIENT__

chdir $dir;
system 'git init' unless -e '.git';

my $server = IO::Socket::INET->new(
	Proto     => 'tcp',
	LocalAddr => $server_ip,
	LocalPort => 9001,
	Listen    => SOMAXCONN,
	Reuse     => 1
) || die $!;


warn "dir: $dir listen: $server_ip:9001\n"
	, "remote-host> echo install | nc $server_ip 9001 > bak ; chmod 755 bak\n"
	, $shell_client
;

while (my $client = $server->accept()) {
	my ($pwd,$command,$path,$message) = split(/\s+/,<$client>,4);
	my $ip = $client->peerhost;

	if ( $pwd eq 'install' ) {
		warn "install on $ip\n";
		print $client $shell_client;
		close($client);
		system 'ssh-copy-id', "root\@$ip" if ! -d $ip;
		next;
	}

	$message ||= '';
	$path = "$pwd/$path" unless $path =~ m{^/};

	warn "$ip [$command] $path | $message\n";


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
		system 'rsync', '-avv', "root\@$ip:$path", "$ip/$path" if $path;
		$message ||= "$command $ip $path";
		system 'git', 'commit', '-m', $message, "$ip/$path";
	} elsif ( $command =~ m{(diff|status|log)} ) {
		my $opt = '--summary' if $command eq 'log';
		print $client `git $command $opt $ip`;
	} elsif ( $command eq 'revert' ) {
		print $client `git checkout -- $ip/$path`;
		system 'rsync', '-avv', "$ip/$path", "root\@$ip:$path";
	} else {
		print $client "Unknown command: $command\n";
	}

}

