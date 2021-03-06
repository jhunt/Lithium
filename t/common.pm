#!/usr/bin/perl

use strict;
use warnings;

use POSIX;
use Lithium;
use LWP::UserAgent;

use Test::More;
use Test::Lithium;

my $LITHIUM_PORT = 11563;
my $PHANTOM_PORT = 16211;
my @phantom = (
	"/usr/bin/phantomjs",
	"--webdriver=$PHANTOM_PORT",
	"--ignore-ssl-errors=yes",
	"--ssl-protocol=TSLv1",
	"/dev/null 2>&1",
);

my %WEBDRIVER_CONFIG = (
	site     => undef,
	browser  => undef,
	host     => undef,
	port     => undef,
);

my $MASTER = $$;

END {
	&stop_depends if $$ == $MASTER;
}

# Set up default selenium configuration
$ENV{BROWSER} ||= "phantomjs";
if ($ENV{BROWSER} eq "phantomjs") {
	note "Using phantomjs for testing";
	plan skip_all => 'Install phantomjs' unless -x $phantom[0];
	$WEBDRIVER_CONFIG{browser} = "phantomjs";
	$WEBDRIVER_CONFIG{host}    = "localhost";
	$WEBDRIVER_CONFIG{port}    =  $PHANTOM_PORT;
} else {
	note "Using $ENV{BROWSER} for testing";
	$WEBDRIVER_CONFIG{host}     = "ae01.buf.synacor.com";
	$WEBDRIVER_CONFIG{port}     =  4451;
	$WEBDRIVER_CONFIG{browser}  = $ENV{BROWSER};
	$WEBDRIVER_CONFIG{platform} = "MAC";
}

# my $T = Test::Builder->new;
my %PIDS;

sub sel_conf
{
	my (%overrides) = @_;
	$WEBDRIVER_CONFIG{$_} = $overrides{$_} for keys %overrides;
	return %WEBDRIVER_CONFIG;
}

sub is_phantom
{
	my $driver = webdriver_driver;
	return ($driver->{browser} eq "phantomjs")
		if $driver;
	return ($ENV{BROWSER} eq "phantomjs") if $ENV{BROWSER};
	return undef;
}

sub start_depends
{
	my $target = &test_site;

	# Fire up Dancer
	$PIDS{dancer} = fork;
	die "Failed to fork Dancer app: $!\n" if $PIDS{dancer} < 0;
	if ($PIDS{dancer}) {
		# pause until we can connect to ourselves
		my $ua = LWP::UserAgent->new();
		my $up = 0;
		for (1..30) {
			sleep 1;
			my $res = $ua->get($target."stats");
			if ($res->is_success) {
				$up = 1;
				last if $res->content =~ m/nodes/i;
			}
		}
		ok($up, "Dancer is up and running at $target")
			or BAIL_OUT "Test website could not be started from Dancer";

		# Fire up Phantom
		if ($ENV{BROWSER} eq "phantomjs") {
			$PIDS{phantom} = fork;
			die "Failed to fork phantomjs: $!\n" if $PIDS{phantom} < 0;
			if ($PIDS{phantom}) {
				# pause until we can connect to webdriver
				my $ua = LWP::UserAgent->new();
				my $up = 0;
				for (1 .. 30) {
					my $res = $ua->get("http://127.0.0.1:$PHANTOM_PORT/sessions");
					$up = $res->is_success; last if $up;
					sleep 1;
				}
				# $T->ok($up, "PhantomJS is up and running at http://127.0.0.1:$PHANTOM_PORT")
				#	or BAIL_OUT "PhantomJS could not start properly, giving up";
			} else {
				# Close stdout/stderr from phantom
				close STDOUT;
				close STDERR;
				exec @phantom;
				exit 1;
			}
		}
		return $target;
	} else {
		close STDOUT;
		close STDERR;
		Lithium::app(
			port         => $LITHIUM_PORT,
			log          => 'console',
			cache_file   => 't/cache.tmp',
			worker_splay =>  5,
			idle_session =>  5,
		);
		exit 1;
	}
	return;
}

sub LITHIUM_PORT
{
	$LITHIUM_PORT;
}
sub PHANTOM_PORT
{
	$PHANTOM_PORT;
}

sub killproc
{
	my ($pid) = @_;
	kill "TERM", $pid;
	return 0 if waitpid($pid, POSIX::WNOHANG);
	sleep 1;

	return 0 if waitpid($pid, POSIX::WNOHANG);
	sleep 1;

	# Commented out because somehow this kills jenkins
	#kill "KILL", $pid;
	return 0;
}

sub stop_depends
{
	stop_webdriver;
	for (keys %PIDS) {
		killproc $PIDS{$_};
		delete $PIDS{$_};
	}
}

sub test_site
{
	my $hostname = `hostname`;
	chomp $hostname;
	return "http://$hostname:$LITHIUM_PORT/";
}

sub spool_a_phantom
{
	my (%options) = @_;
	my @phantom = (
		"/usr/bin/phantomjs",
		"--webdriver='127.0.0.1:$options{port}'",
		"--ignore-ssl-errors=yes",
		"--ssl-protocol=TSLv1",
	);
	push @phantom, "--webdriver-selenium-grid-hub='$options{grid}'"
		if $options{grid};
	my $forked = fork;
	return 0 if $forked < 0;
	if ($forked) {
		# pause until we can connect to webdriver
		my $ua = LWP::UserAgent->new();
		my $up = 0;
		for (1 .. 30) {
			my $res = $ua->get("http://127.0.0.1:$options{port}/sessions");
			$up = $res->is_success; last if $up;
			sleep 1;
		}
	} else {
		# Close stdout/stderr from phantom
		close STDOUT;
		close STDERR;
		exec join(" ", @phantom);
		exit 1;
	}
	return $forked;
}
sub redead_phantoms
{
	for (@_) {
		killproc $_;
	}
}
=head1 t::commom

=head2 DESCRIPTION

=head2 FUNCTIONS

=over

=item start_depends

=item stop_depends

=item spawn

=item reap

=item spool_a_phantom

Takes a hash paramter, grid (Usually $site), and port to run on.

=item redead_phantoms

Kill all the spooled phantom nodes

=back

=head1 AUTHOR

Written by Dan Molik <dmolik@synacor.com>

=cut

1;
