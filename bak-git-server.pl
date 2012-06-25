#!/usr/bin/perl

=head1 bak-git

Simple tracking of remote files in central git repository
with only shell, netcat, rsync and ssh on client

Start server, install on remote-host or upgrade with:

  ./bak-git-server.pl /path/to/backup 192.168.42.42
	[--install remote-host]
	[--upgrade]

C<rsync> traffic is always transfered over ssh, but C<diff> or C<ch> can
still leak sensitive information if C<bak> shell client connects directly
to server host.

Add following line to C<~/.ssh/config> under C<Host> for which you want encrypted
controll channel (or to pass through server ssh hops using C<ProxyCommand>)

  RemoteForward 9001 192.168.42.42:9001

bak command, overview:

  bak add /path
  bak commit [/path [message]]
  bak diff [host:][/path]
  bak status [/path]
  bak log [/path]

  bak show
  bak ch[anges]
  bak revert [host:]/path

  bak cat [host:]/path
  bak grep pattern

  bak - push all changed files to server

  bak add,commit /path

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

# parse ssh config
my $ssh_tunnel;
open(my $ssh_fd, '<', "$ENV{HOME}/.ssh/config");
my $host;
while(<$ssh_fd>) {
	chomp;
	next unless length($_) > 0;
	next if m/^\s*#/;

	if ( /^Host\s+(.+)/i ) {
		$host = $1;
	} elsif ( /^\s+(\S+)\s+(.+)/ ) {
		$ssh_tunnel->{$host}++ if lc($1) eq 'remoteforward' && $2 =~ m/9001/;
	} else {
		die "can't parse $_";
	}
}

sub shell_client {
	my ( $hostname ) = @_;
	my $path = '/tmp/bak';
	my $server = $server_ip;
	$server = '127.0.0.1' if $ssh_tunnel->{$hostname};
warn "# ssh_client $hostname $server";
	open(my $fh, '>', $path);
	print $fh "#!/bin/sh\n";
	print $fh "echo \$USER/\$SUDO_USER $hostname `pwd` \$* | nc $server 9001\n";
	close($fh);
	chmod 0755, $path;
	return $path;
}

sub _kill_ssh {
	while ( my($host,$pid) = each %$ssh_tunnel ) {
		warn "$host kill TERM $pid";
		kill 15, $pid; # TERM
	}
}

#$SIG{INT};
$SIG{TERM} = &_kill_ssh;

chdir $dir;
system 'git init' unless -e '.git';

if ( $upgrade || $install ) {

	my @hosts = grep { -d $_ } glob '*';
	@hosts = ( $install ) if $install;

	foreach my $hostname ( @hosts ) {
		warn "install on $hostname\n";
		system 'ssh-copy-id', "root\@$hostname" if ! -d $hostname;
		my $path = shell_client( $hostname );
		system "scp $path root\@$hostname:/usr/local/bin/";
		system "ssh root\@$hostname apt-get install -y netcat rsync";
	}
} else {
	my $ssh = $ENV{SSH} || 'ssh';
	warn "# start $ssh tunnels...";
	foreach my $host ( keys %$ssh_tunnel ) {
last; # FIXME disabled
		warn "## $host\n";
		my $pid = fork;
		if ( ! defined $pid ) {
			die "fork: $!";
		} elsif ( $pid ) {
#			waitpid $pid, 0;
			warn "FIXME: waitpid $pid";
		} else {
			warn "EXEC $ssh $host";
			exec "$ssh -N root\@$host";
		}

		$ssh_tunnel->{$host} = $pid;
	}
}

warn "dir: $dir listen: $server_ip:9001\n";

my $server = IO::Socket::INET->new(
	Proto     => 'tcp',
#	LocalAddr => $server_ip,
	LocalPort => 9001,
	Listen    => SOMAXCONN,
	Reuse     => 1
) || die $!;


sub rsync {
	warn "# rsync ",join(' ', @_), "\n";
	system 'rsync', @_;
}

sub pull_changes {
	my $hostname = shift;
	system "find $hostname -type f | sed 's,$hostname,,' > /tmp/$hostname.list";
	if ( @_ ) {
		open(my $files, '>>', "/tmp/$hostname.list");
		print $files "$_\n" foreach @_;
		close($files);
	}
	rsync split / /, "-avv --files-from /tmp/$hostname.list root\@$hostname:/ $hostname/";
}

sub mkbasedir {
	my $path = shift;
	$path =~ s{/[^/]+$}{};
	warn "# mkpath $path\n";
	mkpath $path || die $!;
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

	foreach my $command ( split /,/, $command ) { # XXX command loop

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
			rsync( '-avv', "root\@$hostname:$path", "$hostname/$path" );
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
			mkpath $_ foreach grep { ! -e $_ } ( "$hostname/$dir", "$on_host/$dir" );
			rsync( '-avv', "root\@$hostname:$path", "$hostname/$path" );
			rsync( '-avv', "root\@$on_host:$path", "$on_host/$path" );
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
			rsync( '-avv', "$on_host/$path", "root\@$hostname:$path" );
		} else {
			print $client git "checkout -- $hostname/$path";
			rsync( '-avv', "$hostname/$path", "root\@$hostname:$path" );
		}
	} elsif ( $command eq 'cat' ) {
		my $file_path = ( $on_host ? $on_host : $hostname ) . "/$path";
		if ( -r $file_path ) {
			open(my $file, '<', $file_path) || warn "ERROR $file_path: $!";
			while(<$file>) {
				print $client $_;
			}
			close($file);
		} else {
			print $client "ERROR: $file_path: $!\n";
		}
	} elsif ( $command eq 'ls' ) {
		print $client `ls $backup_path`;
	} elsif ( $command eq 'show' ) {
		print $client `git show $rel_path`;
	} elsif ( $command eq 'grep' ) {
		print $client `git log -g --grep=$rel_path`;
	} elsif ( $command eq 'link' ) {
		if ( $on_host ) {
			mkbasedir "$on_host/$path";
			rsync( '-avv', "root\@$on_host:$path", "$on_host/$path" );
			mkbasedir "$hostname/$path";
			link "$on_host/$path", "$hostname/$path";
			rsync( '-avv', "$hostname/$path", "root\@$hostname:$path" );
		} else {
			print $client "ERROR: link requires host:/path\n";
		}
	} else {
		print $client "ERROR: unknown command: $command\n";
	}

	} # XXX command, loop

	close($client);
}

