#!/usr/bin/env perl
# ex:ts=8 sw=4:
# The API-surface gate.
#
# Three invariants hold the tree at its size. Every sub defined in
# lib/Fugu/ has a caller in lib/ or in a test outside its own
# definition line - this repository is a library, so its tests are its
# callers of record. Every module has its one documentation home, a
# .pod sidecar, never none. And every non-core import in lib/ names a
# module that the cpanfile requires.
#
# The caller floor is textual, and therefore a floor: a name that
# collides across the CPAN boundary passes wrongly. The allowlist
# below records such names to check by hand.
#
# The test reads tracked files only, like the sweeps in the sibling
# repositories: build trees hold stale copies until make clean.

use v5.36;
use Test::More;
use FindBin qw($RealBin);
use Module::CoreList;

my $ROOT = "$RealBin/../..";

chdir $ROOT or die "Cannot chdir to $ROOT: $!";

# tracked($pattern):
#	Every tracked path that matches the pattern.
sub tracked ($pattern)
{
	open my $fh, '-|', 'git', 'ls-files', '-z' or return;
	my $out = do { local $/; <$fh> };
	close $fh or return;

	return grep { /$pattern/ && -f $_ } split /\0/, ( $out // '' );
}

# slurp_lines($file):
#	The lines of one file, up to __END__ or __DATA__.
sub slurp_lines ($file)
{
	open my $fh, '<', $file or die "Cannot read $file: $!";
	my @lines;
	while ( my $line = <$fh> ) {
		last if $line =~ /^__(?:END|DATA)__/;
		push @lines, $line;
	}
	close $fh;

	return @lines;
}

my @lib_pm = tracked(qr{^lib/.*\.pm$});
my @tests  = tracked(qr{^t/.*\.t$});
plan skip_all => 'git ls-files gave no file list' unless @lib_pm && @tests;

# --- group one: the caller floor ------------------------------------------

# The names below pass without a caller in the corpus, each for the
# stated reason. A row with no reason fails the self-test, so a name
# cannot slip in bare.
my %ALLOW = (

	# Perl calls these itself
	DESTROY => 'the destructor runs implicitly',
);

subtest 'every allowlist row carries a reason' => sub {
	for my $name ( sort keys %ALLOW ) {
		ok( defined $ALLOW{$name} && length $ALLOW{$name},
			"$name has a reason" );
	}
};

subtest 'the caller floor' => sub {

	# The corpus: every line of lib/ and t/. A library's tests are
	# its callers of record, so a sub that no consumer and no test
	# names is dead weight.
	my @corpus_files = ( @lib_pm, @tests );

	# The definitions under the floor: lib/Fugu/. Protocol:: is out
	# of scope - a codec's .pod contract is its caller.
	my %defined;    # name => [ "file:line", ... ]
	for my $file ( grep {m{^lib/Fugu/}} @lib_pm ) {
		my $n = 0;
		for my $line ( slurp_lines($file) ) {
			$n++;
			next unless $line =~ /^\s*sub\s+([A-Za-z_]\w*)/;
			push @{ $defined{$1} }, "$file:$n";
		}
	}

	cmp_ok( scalar keys %defined, '>', 100,
		'the sweep reads a whole tree of definitions' );

	# Index the corpus once: every name-shaped token of every line,
	# with the definition lines of each sub excluded per name.
	my %seen_at;    # name => { "file:line" => 1 }
	for my $file (@corpus_files) {
		my $n = 0;
		for my $line ( slurp_lines($file) ) {
			$n++;
			for my $token ( $line =~ /([A-Za-z_]\w*)/g ) {
				$seen_at{$token}{"$file:$n"} = 1
				    if exists $defined{$token};
			}
		}
	}

	my @violations;
	for my $name ( sort keys %defined ) {
		next if $ALLOW{$name};

		my %definitions = map { $_ => 1 } @{ $defined{$name} };
		my @callers =
		    grep { !$definitions{$_} } keys %{ $seen_at{$name} // {} };

		next if @callers;

		push @violations,
		    "$_ defines $name, which nothing in lib/ or t/ names"
		    for @{ $defined{$name} };
	}

	is( scalar @violations, 0, 'no sub without a caller' )
	    or diag( join "\n", @violations );

	# The negative control: a name nothing defines or calls must
	# read as caller-less, or the floor proves nothing.
	ok( !exists $seen_at{zz_unused_probe},
		'the corpus holds no caller for an absent name' );
};

# --- group two: documentation completeness, both directions ---------------

subtest 'documentation completeness' => sub {
	my @pods   = tracked(qr{^lib/.*\.pod$});
	my @t_fugu = tracked(qr{^t/fugu/.*\.t$});

	my %pod    = map { $_ => 1 } @pods;
	my %t_fugu = map { $_ => 1 } @t_fugu;
	my %pm     = map { $_ => 1 } @lib_pm;

	my @violations;
	for my $pm (@lib_pm) {
		my $pod = $pm =~ s/\.pm$/.pod/r;
		push @violations, "$pm has no sidecar $pod"
		    unless $pod{$pod};

		if ( $pm =~ m{^lib/Fugu/(\w+)\.pm$} ) {
			my $test = 't/fugu/' . lc($1) . '.t';
			push @violations, "$pm has no $test"
			    unless $t_fugu{$test};
		}
	}

	for my $pod (@pods) {
		my $pm = $pod =~ s/\.pod$/.pm/r;
		push @violations, "$pod has no module $pm"
		    unless $pm{$pm};
	}

	cmp_ok( scalar @lib_pm, '>', 20, 'the sweep reads the whole tree' );
	is( scalar @violations, 0, 'every module has its one home' )
	    or diag( join "\n", @violations );
};

# --- group three: declared dependencies -----------------------------------

# The modules that one cpanfile entry provides beyond its own name.
# HTTP::Message is a distribution; the code uses its parts.
my %PROVIDED_BY = (
	'HTTP::Request'  => 'HTTP::Message',
	'HTTP::Response' => 'HTTP::Message',
);

# Platform modules: part of the OpenBSD base system, absent from
# Module::CoreList and from CPAN alike.
my %PLATFORM = map { $_ => 1 } qw(
    OpenBSD::Pledge
    OpenBSD::Unveil
);

subtest 'declared dependencies' => sub {
	my %required;
	{
		open my $fh, '<', 'cpanfile' or die "Cannot read cpanfile: $!";
		while ( my $line = <$fh> ) {
			$required{$1} = 1
			    if $line =~ /^\s*requires\s+'([^']+)'/;
		}
		close $fh;
	}
	ok( %required, 'the cpanfile declares modules' );

	my @violations;
	for my $file (@lib_pm) {
		my $n = 0;
		for my $line ( slurp_lines($file) ) {
			$n++;
			next
			    unless $line
			    =~ /^\s*(?:use|require)\s+([A-Za-z_][A-Za-z0-9_:]*)/;
			my $module = $1;

			next if $module =~ /^v\d/;
			next if $module =~ /^(?:Fugu|Protocol)\b/;
			next if $PLATFORM{$module};
			next if Module::CoreList::is_core($module);

			my $entry = $PROVIDED_BY{$module} // $module;
			next if $required{$entry};

			push @violations,
			    "$file:$n uses $module, which the cpanfile"
			    . ' does not require';
		}
	}

	is( scalar @violations, 0, 'every import is declared' )
	    or diag( join "\n", @violations );

	# The negative controls: the check must accept a declared
	# module and refuse an absent one.
	ok( $required{'Net::SSH2'}, 'Net::SSH2 is declared' );
	ok( !$required{'JSON::PP::Boolean::Missing'},
		'an absent module is not' );
};

done_testing();
