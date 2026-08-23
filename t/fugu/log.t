#!/usr/bin/env perl
# ex:ts=8 sw=4:
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use_ok('Fugu::Log');

# Test 1: Create logger in stderr mode
{
	my $log = Fugu::Log->new( mode => 'stderr', level => 'debug' );
	ok( defined $log, 'Created stderr logger' );
	isa_ok( $log, 'Fugu::Log' );
}

# Test 2: Create logger in quiet mode
{
	my $log = Fugu::Log->new( mode => 'quiet' );
	ok( defined $log, 'Created quiet logger' );

	# Capture STDERR to show that the quiet mode writes no output
	my $stderr = '';
	{
		local *STDERR;
		open STDERR, '>', \$stderr or die "Cannot capture STDERR: $!";
		$log->debug('test');
		$log->info('test');
	}
	is( $stderr, '', 'Quiet logger produces no output' );
}

# Test 3: Level filtering
{
	my $log = Fugu::Log->new( mode => 'quiet', level => 'warning' );

	# A direct test of the output is not easy. Make sure that the
	# methods exist.
	eval {
		$log->debug('debug message');
		$log->info('info message');
		$log->warning('warning message');
		$log->error('error message');
	};
	ok( !$@, 'All log levels work' );
}

# Test 4: Printf-style formatting
{
	my $log = Fugu::Log->new( mode => 'quiet' );

	eval { $log->info( 'Test %s %d', 'string', 42 ); };
	ok( !$@, 'Printf-style formatting works' );
}

# Test 5: Change log level
{
	my $log = Fugu::Log->new( mode => 'stderr', level => 'error' );

	my $stderr = '';
	{
		local *STDERR;
		open STDERR, '>', \$stderr or die "Cannot capture STDERR: $!";
		$log->debug('suppressed at error level');
	}
	is( $stderr, '', 'debug suppressed before set_level' );

	$log->set_level('debug');
	$stderr = '';
	{
		local *STDERR;
		open STDERR, '>', \$stderr or die "Cannot capture STDERR: $!";
		$log->debug('now visible');
	}
	like( $stderr, qr/now visible/, 'set_level enables debug output' );
}

# Test 6: Default values
{
	my $log = Fugu::Log->new();
	ok( defined $log, 'Created logger with defaults' );
}

# Test 7: Invalid mode
{
	eval { my $log = Fugu::Log->new( mode => 'invalid' ); };
	like( $@, qr/Invalid log mode/, 'Rejects invalid mode' );
}

# Test 8: The module has one name for each level. The syslog
# spellings are level names, not methods.
{
	my $log = Fugu::Log->new( mode => 'quiet' );

	for my $level (qw(debug info notice warning error)) {
		ok( $log->can($level), "$level is a method" );
	}
	for my $alias (qw(warn err crit)) {
		ok( !$log->can($alias), "$alias is not a method" );
	}

	is( Fugu::Log->new( mode => 'quiet', level => 'warn' )->level,
		'info', 'an unknown spelling falls back to info' );
}

# Test 9: level and mode accessors
{
	my $log = Fugu::Log->new( mode => 'quiet', level => 'notice' );
	is( $log->level, 'notice',                 'level returns the name' );
	is( $log->mode, Fugu::Log::MODE_QUIET(), 'mode returns the mode' );

	$log->set_level('debug');
	is( $log->level, 'debug', 'set_level updates the name' );

	$log->set_level('nonsense');
	is( $log->level, 'info', 'an unknown level falls back to info' );
}

# Test 10: reopen keeps the object usable and returns it
{
	my $log = Fugu::Log->new( mode => 'quiet' );
	is( $log->reopen, $log, 'reopen returns the object' );

	my $stderr_log = Fugu::Log->new( mode => 'stderr', level => 'info' );
	$stderr_log->reopen;

	my $stderr = '';
	{
		local *STDERR;
		open STDERR, '>', \$stderr or die "Cannot capture STDERR: $!";
		$stderr_log->info('after reopen');
	}
	like( $stderr, qr/after reopen/, 'a stderr logger still writes' );
}

# Test 11: the process default
{
	my $first = Fugu::Log->default;
	ok( defined $first, 'default creates a logger on the first call' );
	is( Fugu::Log->default, $first, 'default is stable' );

	my $quiet = Fugu::Log->new( mode => 'quiet' );
	is( Fugu::Log->set_default($quiet),
		$quiet, 'set_default returns the new default' );
	is( Fugu::Log->default, $quiet, 'default returns what was set' );

	# A library that logs through the default must never die
	ok( eval { Fugu::Log->default->info('through the default'); 1 },
		'logging through the default works' );
}

# The syslog tests replace the imported Sys::Syslog subs inside the
# Fugu::Log package, so no test opens a live syslog connection. The
# import copies each code reference, so a change in Sys::Syslog alone
# reaches nothing.

# Test 12: syslog mode pins the native transport before openlog
{
	my @calls;
	no warnings 'redefine';
	local *Fugu::Log::setlogsock =
	    sub { push @calls, [ 'setlogsock', @_ ]; 1 };
	local *Fugu::Log::openlog  = sub { push @calls, [ 'openlog', @_ ]; 1 };
	local *Fugu::Log::closelog = sub { 1 };

	my $log = Fugu::Log->new( mode => 'syslog', ident => 'fugutest' );
	is( scalar @calls, 2, 'new makes two syslog calls' );
	is_deeply(
		$calls[0],
		[ 'setlogsock', 'native' ],
		'the first call pins the native transport'
	);
	is( $calls[1][0], 'openlog', 'openlog comes after the pin' );
	is( $calls[1][1], 'fugutest', 'openlog gets the ident' );

	# Test 13: reopen pins the transport again, before openlog
	@calls = ();
	$log->reopen;
	is_deeply(
		$calls[0],
		[ 'setlogsock', 'native' ],
		'reopen pins the native transport again'
	);
	is( $calls[-1][0], 'openlog', 'and openlog comes after the pin' );

	# Free the logger while the overrides still hold, so DESTROY
	# reaches no live closelog
	undef $log;
}

# Test 14: the other modes never touch the transport
{
	my @calls;
	no warnings 'redefine';
	local *Fugu::Log::setlogsock =
	    sub { push @calls, [ 'setlogsock', @_ ]; 1 };
	local *Fugu::Log::openlog = sub { push @calls, [ 'openlog', @_ ]; 1 };

	my $stderr_log = Fugu::Log->new( mode => 'stderr' );
	my $quiet_log  = Fugu::Log->new( mode => 'quiet' );
	$stderr_log->reopen;
	$quiet_log->reopen;
	is_deeply( \@calls, [],
		'a stderr logger and a quiet logger call setlogsock never' );
}

# Test 15: a failed pin is a death at the open, in new and in reopen
{
	my $pin_ok = 1;
	no warnings 'redefine';
	local *Fugu::Log::setlogsock = sub { $pin_ok };
	local *Fugu::Log::openlog    = sub { 1 };
	local *Fugu::Log::closelog   = sub { 1 };

	my $log = Fugu::Log->new( mode => 'syslog' );

	$pin_ok = 0;
	ok( !eval { Fugu::Log->new( mode => 'syslog' ); 1 },
		'new dies when setlogsock reports a failure' );
	like(
		$@,
		qr/Cannot pin the syslog method to native/,
		'and the message names the method'
	);

	ok( !eval { $log->reopen; 1 },
		'reopen dies when setlogsock reports a failure' );
	like(
		$@,
		qr/Cannot pin the syslog method to native/,
		'and the message names the method'
	);

	undef $log;
}

done_testing();
