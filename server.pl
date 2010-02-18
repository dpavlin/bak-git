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
use Getopt::Long;

my $install = 0;
GetOptions(
	'install!' => \$install,
) || die "$!\n";

my ( $dir, $server_ip ) = @ARGV;
die "usage: $0 /backup/directory\n" unless $dir;
$server_ip ||= '127.0.0.1';

my $shell_client = <<__SHELL_CLIENT__;
#!/bin/sh
echo `hostname -s` `pwd` \$* | nc $server_ip 9001
__SHELL_CLIENT__

chdir $dir;
system 'git init' unless -e '.git';

if ( $install ) {
	open(my $fh, '>', '/tmp/bak');
	print $fh $shell_client;
	close($fh);

	foreach my $hostname ( glob '*' ) {
		warn "install on $hostname\n";
		system "scp /tmp/bak root\@$hostname:/usr/local/bin/";
	}
}

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
	my ($hostname,$pwd,$command,$path,$message) = split(/\s+/,<$client>,5);

	if ( $pwd eq 'install' ) {
		warn "install on $hostname\n";
		print $client $shell_client;
		close($client);
		system 'ssh-copy-id', "root\@$hostname" if ! -d $hostname;
		next;
	}

	$message ||= '';
	$path = "$pwd/$path" unless $path =~ m{^/};

	warn "$hostname [$command] $path | $message\n";


	my $dir = $path;
	$dir =~ s{/[^/]+$}{};

	mkpath "$hostname/$dir" unless -e "$hostname/$dir";

	if ( ! $command ) {
		system "find $hostname -type f | sed 's,$hostname,,' > /tmp/$hostname.list";
		system "rsync -avv --files-from /tmp/$hostname.list root\@$hostname:/ $hostname/"
	} elsif ( $command eq 'add' ) {
		system 'rsync', '-avv', "root\@$hostname:$path", "$hostname/$path";
		system 'git', 'add', "$hostname/$path";
	} elsif ( $command eq 'commit' ) {
		system 'rsync', '-avv', "root\@$hostname:$path", "$hostname/$path" if $path;
		$message ||= "$command $hostname $path";
		system 'git', 'commit', '-m', $message, "$hostname/$path";
	} elsif ( $command =~ m{(diff|status|log)} ) {
		my $opt = '--summary' if $command eq 'log';
		print $client `git $command $opt $hostname`;
	} elsif ( $command eq 'revert' ) {
		print $client `git checkout -- $hostname/$path`;
		system 'rsync', '-avv', "$hostname/$path", "root\@$hostname:$path";
	} else {
		print $client "Unknown command: $command\n";
	}

}

