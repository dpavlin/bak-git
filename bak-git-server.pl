#!/usr/bin/perl

=head1 bak-git

Simple tracking of remote files in central git repository
with only shell, netcat, rsync and ssh on client

Start server, install on remote-host or upgrade with:

  ./bak-git-server.pl /path/to/backup 192.168.42.42
	[--install remote-host]
	[--upgrade]

You will want to add following to C<~/.ssh/config>

  RemoteForward 9001 localhost:9001

=cut

use warnings;
use strict;
use autodie;
use IO::Socket::INET;
use File::Path;
use Getopt::Long;

my $upgrade = 0;
my $install;

GetOptions(
	'upgrade!'  => \$upgrade,
	'install=s' => \$install,
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

if ( $upgrade || $install ) {
	open(my $fh, '>', '/tmp/bak');
	print $fh $shell_client;
	close($fh);
	chmod 0755, '/tmp/bak';

	my @hosts = grep { -d $_ } glob '*';
	@hosts = ( $install ) if $install;

	foreach my $hostname ( @hosts ) {
		warn "install on $hostname\n";
		system 'ssh-copy-id', "root\@$hostname" if ! -d $hostname;
		system "scp /tmp/bak root\@$hostname:/usr/local/bin/";
		system "ssh root\@$hostname apt-get install rsync";
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
	, $shell_client
;

sub pull_changes {
	my $hostname = shift;
	system "find $hostname -type f | sed 's,$hostname,,' > /tmp/$hostname.list";
	system "rsync -avv --files-from /tmp/$hostname.list root\@$hostname:/ $hostname/"
}

while (my $client = $server->accept()) {
	my ($hostname,$pwd,$command,$path,$message) = split(/\s+/,<$client>,5);

	$message ||= '';
	$path = "$pwd/$path" unless $path =~ m{^/};

	warn "$hostname [$command] $path | $message\n";


	my $dir = $path;
	$dir =~ s{/[^/]+$}{};

	mkpath "$hostname/$dir" unless -e "$hostname/$dir";

	if ( ! $command ) {
		pull_changes $hostname;
	} elsif ( $command eq 'add' ) {
		system 'rsync', '-avv', "root\@$hostname:$path", "$hostname/$path";
		system 'git', 'add', "$hostname/$path";
	} elsif ( $command eq 'commit' ) {
		system 'rsync', '-avv', "root\@$hostname:$path", "$hostname/$path" if $path;
		$message ||= "$command $hostname $path";
		system 'git', 'commit', '-m', $message, "$hostname/$path";
	} elsif ( $command =~ m{(diff|status|log)} ) {
		my $opt = '--summary' if $command eq 'log';
		pull_changes $hostname if $command eq 'diff';
		print $client `git $command $opt $hostname`;
	} elsif ( $command eq 'revert' ) {
		print $client `git checkout -- $hostname/$path`;
		system 'rsync', '-avv', "$hostname/$path", "root\@$hostname:$path";
	} else {
		print $client "Unknown command: $command\n";
	}

}

