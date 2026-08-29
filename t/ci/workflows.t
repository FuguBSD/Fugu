#!/usr/bin/env perl
# ex:ts=8 sw=4:
# The org pack of FuguBSD/Tooling owns this file. Do not edit a
# synced copy. Edit the canonical copy in FuguBSD/Tooling.
#
# Guards for the workflows of a consumer repository
#
# The canonical setup-perl, setup-uv, and setup-gitleaks actions
# live in FuguBSD/Tooling, and this repository references them across
# repositories.
# Nothing under .github/ runs outside a runner, so the test reads the
# workflows as text and asserts the invariants that only fail in CI:
# that every reference points at the shared action, that every value
# it gets is an environment the action accepts, and that no workflow
# installs dependencies on the side.

use v5.36;
use Test::More;
use FindBin qw($RealBin);

my $workflow = "$RealBin/../../.github/workflows";

use constant ACTION          => 'FuguBSD/Tooling/perl/actions/setup-perl@main';
use constant UV_ACTION       => 'FuguBSD/Tooling/python/actions/setup-uv@main';
use constant GITLEAKS_ACTION => 'FuguBSD/Tooling/actions/setup-gitleaks@main';

my %ENVIRONMENTS = map { $_ => 1 } qw(runtime test develop);

# _slurp($path):
#	Whole file as text, or undef with a failed assertion.
sub _slurp ($path)
{
	open my $fh, '<', $path or do {
		fail("$path is readable");
		return;
	};
	local $/ = undef;
	my $content = <$fh>;
	close $fh;

	return $content;
}

opendir my $dh, $workflow or plan skip_all => 'no workflows';
my @files = sort grep { /\.yml\z/ } readdir $dh;
closedir $dh;

ok( scalar @files, 'workflows found' );

my $users = 0;
for my $file (@files) {
	my $text  = _slurp("$workflow/$file") // next;
	my @lines = split /\n/, $text;

	# No workflow installs dependencies itself. The shared action
	# owns the whole install, so one step per job is the rule.
	my @own = grep { m{^\s+run:.*\bmake\s+deps\b} } @lines;
	is( scalar @own, 0, "$file runs no deps target of its own" )
	    or diag( join "\n", @own );

	for my $i ( 0 .. $#lines ) {
		next unless $lines[$i] =~ m{uses:\s*(\S*setup-perl\S*)\s*$};
		my $ref = $1;
		$users++;

		is( $ref, ACTION,
			      "$file line @{[$i + 1]} references"
			    . ' the shared action' );

		my $env;
		for my $j ( $i + 1 .. $#lines ) {
			last if $lines[$j] =~ /^\s+-\s/;
			if ( $lines[$j] =~ /^\s+dependencies:\s*"?(\w+)"?\s*$/ )
			{
				$env = $1;
				last;
			}
		}

		# To omit it is fine. That is what the default is for.
		# But a value that is not an environment is a job that
		# installs nothing.
		ok(
			!defined $env || exists $ENVIRONMENTS{$env},
			"$file line @{[$i + 1]}: "
			    . ( $env // '(default)' )
			    . ' is a known environment'
		);
	}

	# The same pin for the uv toolchain: a stale or wrong setup-uv
	# path fails here, not many minutes into a runner job.
	for my $i ( 0 .. $#lines ) {
		next unless $lines[$i] =~ m{uses:\s*(\S*setup-uv\S*)\s*$};
		is( $1, UV_ACTION,
			      "$file line @{[$i + 1]} references"
			    . ' the shared uv action' );
	}

	# The same pin for gitleaks: the gate reads every secret
	# finding, so only the pinned action installs the binary.
	for my $i ( 0 .. $#lines ) {
		next
		    unless $lines[$i] =~ m{uses:\s*(\S*setup-gitleaks\S*)\s*$};
		is( $1, GITLEAKS_ACTION,
			      "$file line @{[$i + 1]} references"
			    . ' the shared gitleaks action' );
	}
}

# A repository with no Perl dependencies uses no setup-perl at all.
# The rules above apply to each use, not to the count.
note("setup-perl uses found: $users");

# The gitleaks gate needs the full git history (WFL-GITLEAKS-2): a
# shallow checkout hides old commits from the scan. The check
# workflow must run the gate after a full checkout, in the same job.
# A full checkout in a sibling job feeds a different runner. The
# gate runs through make gitleaks, or through make check, which
# runs every gate per MK-VERBS-3.
subtest 'the check workflow runs the gitleaks gate' => sub {
	my $path = "$workflow/check.yml";
	plan skip_all => 'no check workflow' unless -f $path;

	my $text = _slurp($path) // q{};

	# A block starts at each two-space key: every job, and also
	# the triggers under on:. A trigger block never runs make, so
	# the grep lands on the gate jobs only.
	my @blocks = split /^(?=  [A-Za-z0-9_-]+:[ \t]*$)/m, $text;
	my @gate   = grep { /run:\s*make (?:check|gitleaks)\b/ } @blocks;
	ok( scalar @gate, 'check.yml runs the gitleaks gate' );
	ok(
		( grep { /fetch-depth:\s*0\b/ } @gate ),
		'and a gate job holds a full checkout'
	);
};

# The supply-chain rule: no third-party action. A workflow may use
# GitHub's own actions/, the FuguBSD organization's, or a local path -
# nothing else runs foreign code in CI.
subtest 'workflows use no third-party action' => sub {
	opendir my $dh, $workflow or do {
		fail('.github/workflows is readable');
		return;
	};
	my @files = sort grep { /\.yml\z/ } readdir $dh;
	closedir $dh;

	my @violations;
	for my $file (@files) {
		my $text = _slurp("$workflow/$file") // next;
		my $n    = 0;
		for my $line ( split /\n/, $text ) {
			$n++;
			next unless $line =~ /^\s+uses:\s*(\S+)/;
			my $ref = $1;
			next if $ref =~ m{^\./};
			next if $ref =~ m{^actions/};
			next if $ref =~ m{^FuguBSD/};
			push @violations, "$file:$n uses $ref";
		}
	}

	is( scalar @violations, 0, 'every action is first-party' )
	    or diag( join "\n", @violations );
};

done_testing();
