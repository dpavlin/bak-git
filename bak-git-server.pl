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

bak command overview:

  bak add /path
  bak commit [/path [message]]
  bak diff [host:][/path]
  bak status [/path]
  bak log [/path]

  bak ch[anges]
  bak revert [host:]/path

  bak - push all changed files to server

See L<http://blog.rot13.org/bak-git> for more information

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
die "usage: $0 /backup/directory 127.0.0.1\n" unless $dir;
$server_ip ||= '127.0.0.1';

my $shell_client = <<__SHELL_CLIENT__;
#!/bin/sh
echo \$USER/\$SUDO_USER `hostname` `pwd` \$* | nc $server_ip 9001
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
		system "ssh root\@$hostname apt-get install -y rsync";
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
	if ( @_ ) {
		open(my $files, '>>', "/tmp/$hostname.list");
		print $files "$_\n" foreach @_;
		close($files);
	}
	system "rsync -avv --files-from /tmp/$hostname.list root\@$hostname:/ $hostname/"
}

while (my $client = $server->accept()) {
	my $line = <$client>;
	chomp($line);
	warn "<<< $line\n";
	my ($user,$hostname,$pwd,$command,$rel_path,$message) = split(/\s+/,$line,6);
	$hostname =~ s/\..+$//;

	my $on_host = '';
	if ( $rel_path =~ s/^([^:]+):(.+)$/$2/ ) {
		if ( -e $1 ) {
			$on_host = $1;
		} else {
			print $client "host $1 doesn't exist in backup\n";
			next;
		}
	}
	my $path = $rel_path =~ m{^/} ? $rel_path : "$pwd/$rel_path";

	warn "$hostname [$command] $on_host:$path | $message\n";

	my $args_message = $message;

	$message ||= "$path [$command]";
	$message = "$hostname: $message";

	my $dir = $path;
	$dir =~ s{/[^/]+$}{};

	my $backup_path = -e "$hostname/$path" ? "$hostname/$path" : $hostname;

	sub git {
		my $args = join(' ',@_);
		warn "# git $args\n";
		my $out = `git $args`;
		warn "$out\n# [", length($out), " bytes]\n" if defined $out;
		return $out;
	}

	if ( ! $command ) {
		pull_changes $hostname;
	} elsif ( $command eq 'add' ) {
		mkpath "$hostname/$dir" unless -e "$hostname/$dir";
		while ( $path ) {
			system 'rsync', '-avv', "root\@$hostname:$path", "$hostname/$path";
			print $client git 'add', "$hostname/$path";

			$args_message =~ s/^(.+)\b// || last;
			$path = $1;
			warn "? $path";
		}
	} elsif ( $command eq 'commit' ) {
		pull_changes $hostname;
		$message =~ s/'/\\'/g;
		$user =~ s/\/$//;
		print $client git( "commit -m '$message' --author '$user <$hostname>' $backup_path" );
	} elsif ( $command =~ m{(diff|status|log|ch)} ) {
		$command .= ' --stat' if $command eq 'log';
		$command = 'log --patch-with-stat' if $command =~ m/^ch/;
		pull_changes( $hostname ) if $command eq 'diff';
		if ( $on_host ) {
			system 'rsync', '-avv', "root\@$hostname:$path", "$hostname/$path";
			system 'rsync', '-avv', "root\@$on_host:$path", "$on_host/$path";
			open(my $diff, '-|', "diff -Nuw $hostname$path $on_host$path");
			while(<$diff>) {
				print $client $_;
			}
		} else {
			# commands without path will show host-wide status/changes
			my $backup_path = $path ? "$hostname/$path" : "$hostname/";
			# hostname must end with / to prevent error from git:
			# ambiguous argument 'arh-hw': both revision and filename
			# to support branches named as hosts
			print $client git($command, $backup_path);
		}
	} elsif ( $command eq 'revert' ) {
		if ( $on_host ) {
			system 'rsync', '-avv', "$on_host/$path", "root\@$hostname:$path";
		} else {
			print $client git "checkout -- $hostname/$path";
			system 'rsync', '-avv', "$hostname/$path", "root\@$hostname:$path";
		}
	} else {
		print $client "Unknown command: $command\n";
	}

}

