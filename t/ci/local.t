#!/usr/bin/env perl
# ex:ts=8 sw=4:
# The org pack of FuguBSD/Tooling owns this file. Do not edit a
# synced copy. Edit the canonical copy in FuguBSD/Tooling.
#
# Guards for the consumer hook mk/local.mk
#
# mk/local.mk must not define a target that a synced fragment
# defines (MK-LOCAL-4). On a second recipe for one target, make
# prints only a warning, and the include order picks the recipe. The
# test reads the make files as text, so it runs without a build.

use v5.36;
use Test::More;
use FindBin qw($RealBin);

my $root = "$RealBin/../..";

# _targets($path):
#	The names of the targets that one make file defines.
sub _targets ($path)
{
	open my $fh, '<', $path or do {
		fail("$path is readable");
		return;
	};
	local $/ = undef;
	my $text = <$fh>;
	close $fh;
	$text =~ s/\\\n[ \t]*/ /g;

	# A rule line can name several targets before the colon, and an
	# inline recipe can follow it. An assignment line and a recipe
	# line are not rule lines.
	my @names;
	for my $line ( split /\n/, $text ) {
		next if $line =~ /^\.PHONY/ || $line =~ /^\t/;
		next unless $line =~ /^([^:=#\t][^:=]*):(?:[^=]|$)/;
		push @names, split q{ }, $1;
	}

	return @names;
}

plan skip_all => 'no mk/local.mk' unless -f "$root/mk/local.mk";

my %local = map { $_ => 1 } _targets("$root/mk/local.mk");

for my $fragment (qw(mk/org.mk mk/perl.mk mk/python.mk)) {
	next unless -f "$root/$fragment";
	my @clashes = grep { $local{$_} } _targets("$root/$fragment");
	is( "@clashes", q{}, "mk/local.mk redefines no target of $fragment" );
}

done_testing();
