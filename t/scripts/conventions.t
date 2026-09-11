#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Guards for scripts/ that no single script's own test would catch
#
# Names in scripts/ carry no extension. Thus only the shebang says
# what language a file is in. Several call sites invoke them as bare
# paths: the Makefile, scripts/deps, CI. A lost exec bit or a broken
# shebang thus fails at use, not at build.

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);
use Test::More;
use File::Find ();
use FindBin    qw($RealBin);

my $root = "$RealBin/../..";
my $dir  = "$root/scripts";

# Named, not globbed: a script that disappears must fail here. The
# list must not shrink silently.
my @scripts = qw(deps dist ftp spec-check spec-coverage ste-lint);

# The pragma block of the repository floor, in order. lib/CLAUDE.md
# states it, and spec/architecture.md states the floor.
my @BLOCK = (
	'use v5.34;',
	'use warnings;',
	q{use experimental 'signatures';},
	'no feature qw(indirect multidimensional bareword_filehandles);',
);

# A pack of FuguBSD/Tooling owns a synced file, and that file keeps
# the floor of its pack. A comment at the head of the file says so.
# The test reads that head block alone, so a file that quotes the
# sentence lower down cannot exempt itself.
my $MARKER = qr{^\# .* pack \s+ of \s+ FuguBSD/Tooling \s+ owns \s+
		this \s+ file}mx;

# The version pragma, in both of its spellings. `use v5.34;` and
# `use 5.034;` set the same floor, so a scan that reads one form only
# lets the other one through. The capture holds the minor version,
# with or without a leading zero.
my $PRAGMA = qr{
	^ [ \t]* use [ \t]+ v? 5 \. (\d{2,3}) \d* (?: \. \d+ )? [ \t]* ;
}mx;

# _slurp($path):
#	The whole file as text, or undef.
sub _slurp ($path)
{
	open my $fh, '<', $path or return;
	local $/ = undef;
	my $text = <$fh>;
	close $fh;

	return $text;
}

# _head($text):
#	The comment block at the head of $text: the shebang, the
#	modeline, the licence header, and every comment line before the
#	first line of code.
sub _head ($text)
{
	return q{} unless defined $text;
	my ($head) = $text =~ /\A((?:[ \t]*(?:\#[^\n]*)?\n)*)/;

	return $head // q{};
}

# _body($text):
#	$text with the head block and one package statement removed. The
#	pragma block opens the result, in a file that holds one.
sub _body ($text)
{
	my $body = $text;
	$body =~ s/\A(?:[ \t]*(?:\#[^\n]*)?\n)*//;
	$body =~ s/\Apackage\s[\w:]+;\n//;
	$body =~ s/\A(?:[ \t]*(?:\#[^\n]*)?\n)*//;

	return $body;
}

# _floor($text):
#	The perl version that the version pragma at the head of $text
#	names, as a number that compares with $]. A pragma lower down,
#	such as one in a heredoc that a test writes out, does not count.
#	Text with no pragma at its head returns undef.
sub _floor ($text)
{
	return unless defined $text;
	return unless _body($text) =~ /\A$PRAGMA/;

	return sprintf '5.%03d', $1 + 0;
}

# _opens($text):
#	True when the pragma block of the floor opens the body of $text.
sub _opens ($text)
{
	return 0 == index _body($text), join "\n", @BLOCK;
}

# _use($version):
#	One version pragma, as a line. The sweep below reads this file
#	and fails a literal pragma above the floor, so a fixture builds
#	one here instead of spelling it out.
sub _use ($version)
{
	return "use $version;\n";
}

# The helpers above are the whole floor gate, so each one holds its
# own assertion. A revert of the head-only marker, of the anchor of
# _floor, or of the second spelling of the pragma must fail here. The
# fixtures are strings, so this subtest reads no file.
subtest 'the helpers of the floor gate' => sub {

	# The marker of a synced file, at the left margin. It sits below
	# the head of this file, so the sweep below must still read this
	# file. The exempt set there proves it.
	my $mark = <<'MARK';
# The org pack of FuguBSD/Tooling owns this file. Do not edit a
# synced copy. Edit the canonical copy in FuguBSD/Tooling.
MARK

	my $shebang = "#!/usr/bin/env perl\n";
	my $licence = "# Copyright (c) 2026 Dick Olsson\n#\n";
	my $package = "package Fugu::Example;\n";
	my $block   = join "\n", @BLOCK;
	my $child   = "print <<'PERL';\n" . _use('v5.36') . "PERL\n";

	like( _head( $shebang . $mark ), $MARKER,
		'the marker in the head block exempts a file' );
	unlike( _head( $shebang . $block . "\n" . $mark ), $MARKER,
		'the marker below the head exempts nothing' );

	is( _floor( $shebang . $child ), undef,
		'_floor reads no pragma below the head' );
	is( _floor( _use('v5.36') ), '5.036', '_floor reads use v5.36' );
	is( _floor( _use('5.036') ), '5.036',
		'_floor reads use 5.036 as the same floor' );

	ok( _opens( $shebang . $licence . $block ),
		'the block opens the body after a licence header' );
	ok( _opens( $shebang . $licence . $package . $block ),
		'the block opens the body after a package line' );
	ok( _opens( $package . $licence . $block ),
		'the block opens the body after a package line above the licence' );

	( my $indented = $block ) =~ s/^/\t/mg;
	ok( !_opens( $shebang . $licence . $indented ),
		'an indented block does not open the body' );
	ok( !_opens( $shebang . $licence . "use strict;\n" . $block ),
		'a statement before the block does not open the body' );
};

for my $name (@scripts) {
	my $path = "$dir/$name";

	ok( -f $path, "scripts/$name exists" ) or next;
	ok( -x $path, "scripts/$name is executable" );

	open my $fh, '<', $path or do {
		fail("scripts/$name is readable");
		next;
	};
	my $shebang = <$fh>;
	close $fh;

	like( $shebang, qr{\A\#!\S*/(?:env )?(?:sh|perl)\b},
		"scripts/$name has an sh or perl shebang" );
}

# Every Perl script compiles. make lint and make tidy already read
# them, but neither runs the compiler. CI's perl -cw sweep covers only
# lib/ and bin/.
#
# A synced script can name a perl above the one that runs this file.
# The compiler then reports the version and stops, which says nothing
# about the script. The sweep reads the version pragma of each script
# and skips the compile in that case.
for my $name (@scripts) {
	my $path = "$dir/$name";
	next unless -f $path;

	my $text = _slurp($path) // next;
	next unless $text =~ /\A\#!.*perl/;

	my $floor = _floor($text);
    SKIP: {
		skip "scripts/$name needs perl $floor, this perl is $]", 1
		    if defined $floor && $] < $floor;

		my $output = `$^X -c "$path" 2>&1`;
		is( $? >> 8, 0, "scripts/$name compiles" ) or diag($output);
	}
}

# Every Fugu-owned Perl file starts with the pragma block of the
# repository floor. A file that a Tooling pack owns keeps the floor of
# that pack, so the check skips it.
subtest 'every Fugu-owned Perl file holds the pragma block' => sub {
	my @files;
	File::Find::find(
		sub {
			push @files, $File::Find::name
			    if -f $_ && /\.(?:pm|t)\z/;
		},
		"$root/lib",
		"$root/t"
	);

	# ARC-COREPERL-3 governs every Fugu-owned script, not one name.
	# @scripts holds every script, and the marker below drops the
	# ones that a Tooling pack owns.
	push @files, map {"$dir/$_"} @scripts;

	my ( @exempt, @violations, $checked );
	for my $path ( sort @files ) {
		my $name = $path =~ s{^\Q$root\E/}{}r;
		my $text = _slurp($path);
		unless ( defined $text ) {
			push @violations, "$name is unreadable";
			next;
		}
		if ( _head($text) =~ $MARKER ) {
			push @exempt, $name;
			next;
		}
		$checked++;

		# The block governs the whole file, so nothing but a
		# comment, a blank line, and the package statement can
		# come before it. Perl::Critic wants the package
		# statement first, and the pragmas are lexical from
		# their own line, so that order is the only one that
		# satisfies both.
		push @violations, "$name does not open with the pragma block"
		    unless _opens($text);

		# One version pragma, and it is the floor. A second one
		# hides in a child source that a test writes out.
		while ( $text =~ /$PRAGMA/g ) {
			my $minor = $1 + 0;
			next if $minor == 34;
			push @violations, "$name holds use v5.$minor";
		}
	}

	# The exempt set, pinned by name. `t/scripts/dist.t` holds "The
	# perl pack of FuguBSD/Tooling owns `scripts/dist`" in its own head
	# block, one word away from the sentence, so it must stay out. This
	# file quotes the sentence below its head, so a marker that reads
	# the whole file puts this file in.
	is_deeply(
		\@exempt,
		[
			qw(scripts/deps scripts/dist scripts/ftp),
			qw(scripts/spec-check scripts/ste-lint),
			qw(t/ci/local.t t/ci/workflows.t),
		],
		'exactly the pack-owned files are exempt'
	);

	ok( $checked, "the sweep read $checked Fugu-owned Perl files" );
	is( scalar @violations, 0, 'every file holds the pragma block' )
	    or diag( join "\n", @violations );
};

# Nothing under scripts/ regained an extension or an underscore
{
	opendir my $dh, $dir or die "opendir $dir: $!";
	my @found = sort grep { !/\A\.\.?\z/ } readdir $dh;
	closedir $dh;

	is_deeply( \@found, [ sort @scripts ],
		'scripts/ holds exactly the expected files' );

	my @odd = grep { /[_.]/ } @found;
	is_deeply( \@odd, [], 'no script name has an underscore or extension' );
}

done_testing();
