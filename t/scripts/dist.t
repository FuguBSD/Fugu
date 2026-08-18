#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Unit tests for scripts/dist, the distribution-tarball builder
#
# The test builds a real dist from this checkout into a temporary
# directory, extracts it, and asserts the shape a cpanm install needs.

use v5.36;
use Test::More;
use Cwd        qw(getcwd);
use FindBin    qw($RealBin);
use File::Find ();
use File::Temp qw(tempdir);

my $script = "$RealBin/../../scripts/dist";
my $root   = "$RealBin/../..";
ok( -x $script, 'dist script is executable' );

my $out = tempdir( CLEANUP => 1 );

# The version is explicit, so the script never needs git here, and the
# test runs the same from a tarball of the tree.
{
	my $cwd = getcwd();
	chdir $root or die "chdir $root: $!";
	my $output = `$script --version 0.1 --out '$out' 2>&1`;
	my $exit   = $? >> 8;
	chdir $cwd or die "chdir $cwd: $!";

	is( $exit, 0, 'dist exits 0' ) or diag($output);
}

my $tarball = "$out/Fugu-0.1.tar.gz";
ok( -f $tarball, 'the tarball exists under its versioned name' );

# A malformed version fails before any staging.
{
	my $cwd = getcwd();
	chdir $root or die "chdir $root: $!";
	my $output = `$script --version nonsense --out '$out' 2>&1`;
	my $exit   = $? >> 8;
	chdir $cwd or die "chdir $cwd: $!";

	isnt( $exit, 0, 'a malformed version exits non-zero' );
	like( $output, qr/not dotted-decimal/, 'and says why' );
}

my $work = tempdir( CLEANUP => 1 );
system( 'tar', '-xzf', $tarball, '-C', $work ) == 0
    or BAIL_OUT('cannot extract the tarball');
my $tree = "$work/Fugu-0.1";

subtest 'the staged tree is a standard Perl distribution' => sub {
	ok( -f "$tree/Makefile.PL", 'Makefile.PL is at the root' );
	ok( -f "$tree/MANIFEST",    'MANIFEST is at the root' );
	ok( -f "$tree/LICENSE",     'the license ships' );
	ok( !-f "$tree/Makefile",
		'the hand-written BSD Makefile does not ship' );

	ok( -f "$tree/lib/Fugu/Daemon.pm",   'a module ships' );
	ok( -f "$tree/lib/Protocol/Imsg.pm", 'the codec ships' );
	ok( -f "$tree/lib/Fugu/Daemon.pod",  'a sidecar ships' );
	ok( -f "$tree/t/fugu/daemon.t",      'a test ships' );

	my $output = `$^X -c "$tree/Makefile.PL" 2>&1`;
	is( $? >> 8, 0, 'Makefile.PL compiles' ) or diag($output);
};

subtest 'the MANIFEST lists exactly the staged files' => sub {
	open my $fh, '<', "$tree/MANIFEST" or do {
		fail('MANIFEST is readable');
		return;
	};
	chomp( my @listed = <$fh> );
	close $fh;

	my @found;
	File::Find::find(
		{
			wanted => sub {
				return unless -f $_;
				my $rel = $File::Find::name =~ s{^\Q$tree\E/}{}r;
				push @found, $rel;
			},
			no_chdir => 1,
		},
		$tree
	);

	is_deeply( [ sort @listed ], [ sort @found ],
		'no file outside the MANIFEST, none missing' );
};

subtest 'the Makefile.PL declares the identity' => sub {
	open my $fh, '<', "$tree/Makefile.PL" or do {
		fail('Makefile.PL is readable');
		return;
	};
	my $text = do { local $/; <$fh> };
	close $fh;

	like( $text, qr/NAME\s+=>\s+'Fugu'/,     'the NAME anchors PAUSE' );
	like( $text, qr/VERSION\s+=>\s+'0\.1'/,  'the version is the input' );
	like( $text, qr/MIN_PERL_VERSION/,       'the perl floor is stated' );
	like( $text, qr/'lib\/Fugu\/Daemon\.pm'/, 'the PM map lists modules' );
};

done_testing();
