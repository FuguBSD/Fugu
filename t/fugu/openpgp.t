#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Guards for Fugu::OpenPGP
#
# The two fixtures are real armored keys of gpg(1), committed as
# files. A test must not run gpg(1): the module needs no command, so
# its test needs none either. The Ed25519 key packs its public key
# packet behind a one-byte length, and the RSA key needs a two-byte
# length. Both header paths therefore read a real key.
#
# The expected fingerprint of each fixture comes from
# 'gpg --list-keys --with-colons' at the time the fixture was made.

use v5.36;
use Test::More;
use MIME::Base64 qw(encode_base64);
use FindBin      qw($RealBin);
use lib "$RealBin/../../lib";

use_ok('Fugu::OpenPGP');

# The fixtures, with the fingerprint that gpg(1) reported.
my %FIXTURE = (
	'openpgp-ed25519.asc' => {
		fingerprint => '5E0B59F43C61B6AEAB99BA27ED353DC0A93A0BF6',
		note        => 'a one-byte packet length',
	},
	'openpgp-rsa.asc' => {
		fingerprint => 'FB1AE38CBE7138D5F87232D4C52EC81D604D60D6',
		note        => 'a two-byte packet length',
	},
);

# slurp($name):
#	The text of a fixture beside this test file.
sub slurp ($name)
{
	my $path = "$RealBin/$name";
	open my $fh, '<', $path or die "Cannot read $path: $!";
	local $/ = undef;
	my $text = <$fh>;
	close $fh;
	return $text;
}

subtest 'the module runs no command' => sub {
	for my $name (qw(new sign import verify)) {
		ok( !Fugu::OpenPGP->can($name), "no $name method exists" );
	}
};

subtest 'decode_armor reads each fixture' => sub {
	for my $name ( sort keys %FIXTURE ) {
		my ( $binary, $reason ) =
		    Fugu::OpenPGP->decode_armor( slurp($name) );

		ok( defined $binary, "$name decodes" )
		    or diag($reason);
		is( $reason, undef, "$name reports no reason" );
		ok( length($binary) > 0, "$name gives bytes" );

		# The armor holds a public key packet first, so the
		# high bit of the first byte is set.
		ok( ord( substr $binary, 0, 1 ) & 0x80,
			"$name starts on a packet header" );
	}
};

subtest 'fingerprint matches the answer of gpg(1)' => sub {
	for my $name ( sort keys %FIXTURE ) {
		my $binary = Fugu::OpenPGP->decode_armor( slurp($name) );
		my ( $got, $reason ) = Fugu::OpenPGP->fingerprint($binary);

		is( $got, $FIXTURE{$name}{fingerprint},
			"$name gives the fingerprint of gpg(1)"
			    . " ($FIXTURE{$name}{note})" )
		    or diag($reason);
		is( $reason, undef, "$name reports no reason" );
	}
};

subtest 'the checksum line catches a damaged body' => sub {
	my $text = slurp('openpgp-ed25519.asc');

	# A flipped checksum character. The body is intact, so only
	# the comparison finds this.
	my $flipped = $text;
	$flipped =~ s/^=(.)/'=' . ( $1 eq 'A' ? 'B' : 'A' )/me;
	my ( $binary, $reason ) = Fugu::OpenPGP->decode_armor($flipped);
	is( $binary, undef, 'a flipped checksum fails' );
	like( $reason, qr/checksum mismatch/, 'and the reason says so' );

	# A dropped body line. This is the dangerous case: without the
	# checksum a decoder accepts the truncated key, and a
	# truncated key has a fingerprint of its own.
	my @lines   = split /\n/, $text;
	my @shorter = grep { !/\Am[A-Za-z0-9+\/]/ } @lines;
	( $binary, $reason ) =
	    Fugu::OpenPGP->decode_armor( join "\n", @shorter );
	is( $binary, undef, 'a dropped body line fails' );
	like( $reason, qr/checksum mismatch|no base64 body/,
		'and the reason says so' );
};

subtest 'decode_armor holds the delimiters' => sub {
	my $text = slurp('openpgp-ed25519.asc');

	my ( $binary, $reason ) = Fugu::OpenPGP->decode_armor('no armor here');
	is( $binary, undef, 'text with no delimiter fails' );
	like( $reason, qr/no BEGIN PGP delimiter/, 'and the reason says so' );

	my $no_end = $text;
	$no_end =~ s/-----END PGP PUBLIC KEY BLOCK-----//;
	( $binary, $reason ) = Fugu::OpenPGP->decode_armor($no_end);
	is( $binary, undef, 'a block with no end delimiter fails' );
	like( $reason, qr/no END PGP delimiter/, 'and the reason says so' );

	# A begin line of one type with an end line of another is a
	# spliced file.
	my $spliced = $text;
	$spliced =~ s/-----END PGP PUBLIC KEY BLOCK-----/-----END PGP MESSAGE-----/;
	( $binary, $reason ) = Fugu::OpenPGP->decode_armor($spliced);
	is( $binary, undef, 'two block types fail' );
	like( $reason, qr/two block types/, 'and the reason says so' );

	( $binary, $reason ) = Fugu::OpenPGP->decode_armor(undef);
	is( $binary, undef, 'undef fails' );
	like( $reason, qr/undef/, 'and the reason says so' );
};

subtest 'decode_armor needs a checksum line' => sub {
	my $text = slurp('openpgp-ed25519.asc');
	my $none = $text;
	$none =~ s/^=\S{4}\n//m;

	my ( $binary, $reason ) = Fugu::OpenPGP->decode_armor($none);
	is( $binary, undef, 'a block with no checksum line fails' );
	like( $reason, qr/no checksum line/, 'and the reason says so' );
};

subtest 'decode_armor reads an armor header' => sub {
	my $text = slurp('openpgp-ed25519.asc');

	# gpg(1) writes no header today, so the test adds one. A
	# reader must skip it and still decode the body.
	my $headed = $text;
	$headed =~
	    s/(-----BEGIN PGP PUBLIC KEY BLOCK-----\n)/$1Comment: a header\n\n/;

	my ( $binary, $reason ) = Fugu::OpenPGP->decode_armor($headed);
	ok( defined $binary, 'a block with an armor header decodes' )
	    or diag($reason);
	is(
		Fugu::OpenPGP->fingerprint($binary),
		$FIXTURE{'openpgp-ed25519.asc'}{fingerprint},
		'and the header changes no fingerprint'
	);
};

subtest 'decode_armor reads each line-ending and header shape' => sub {
	my $text = slurp('openpgp-ed25519.asc');
	my $want = $FIXTURE{'openpgp-ed25519.asc'}{fingerprint};

	# RFC 4880 writes a blank line after the delimiter even with
	# no header, and gpg(1) does the same. A producer that omits
	# it holds a body on the first line, and the body must still
	# decode. A header test that asks whether the block holds a
	# blank line anywhere gets this wrong: the split of the body
	# always leaves a trailing empty element.
	my $no_blank = $text;
	$no_blank =~ s/(-----BEGIN PGP PUBLIC KEY BLOCK-----\n)\n/$1/;
	is( scalar Fugu::OpenPGP->fingerprint(
			scalar Fugu::OpenPGP->decode_armor($no_blank) ),
		$want, 'a block with no blank line decodes' );

	# Two headers, then the blank line.
	my $two = $text;
	$two =~
	    s/(-----BEGIN PGP PUBLIC KEY BLOCK-----\n)/$1Comment: one\nVersion: 9\n/;
	is( scalar Fugu::OpenPGP->fingerprint(
			scalar Fugu::OpenPGP->decode_armor($two) ),
		$want, 'a block with two armor headers decodes' );

	# Armor is text, so a block that travelled through email
	# holds CRLF. The delimiter lines carry it too.
	my $crlf = $text;
	$crlf =~ s/\n/\r\n/g;
	is( scalar Fugu::OpenPGP->fingerprint(
			scalar Fugu::OpenPGP->decode_armor($crlf) ),
		$want, 'a block with CRLF line endings decodes' );

	my $crlf_no_blank = $no_blank;
	$crlf_no_blank =~ s/\n/\r\n/g;
	is( scalar Fugu::OpenPGP->fingerprint(
			scalar Fugu::OpenPGP->decode_armor($crlf_no_blank) ),
		$want, 'CRLF with no blank line decodes' );

	# The method must not change the string of the caller.
	my $copy = $text;
	Fugu::OpenPGP->decode_armor($copy);
	is( $copy, $text, 'the method leaves the input string alone' );

	# A first line that is neither a header nor base64 must fail.
	my $garbage = $text;
	$garbage =~
	    s/(-----BEGIN PGP PUBLIC KEY BLOCK-----\n)\n/$1garbage here\n\n/;
	my ( $binary, $reason ) = Fugu::OpenPGP->decode_armor($garbage);
	is( $binary, undef, 'a garbage first line fails' );
	like( $reason, qr/not a base64 body line/, 'and the reason says so' );
};

subtest 'fingerprint holds the first packet to a public key' => sub {
	# A literal data packet, tag 11, in the old format with a
	# one-byte length.
	my $literal = chr( 0x80 | ( 11 << 2 ) ) . chr(3) . 'abc';
	my ( $got, $reason ) = Fugu::OpenPGP->fingerprint($literal);
	is( $got, undef, 'a literal data packet fails' );
	like( $reason, qr/tag 11, and not a public key/,
		'and the reason names the tag' );

	# A version 3 public key packet. Only version 4 has this
	# fingerprint form.
	my $v3 = chr(0x98) . chr(4) . chr(3) . 'xyz';
	( $got, $reason ) = Fugu::OpenPGP->fingerprint($v3);
	is( $got, undef, 'a version 3 packet fails' );
	like( $reason, qr/version 3, and not 4/, 'and the reason says so' );

	( $got, $reason ) = Fugu::OpenPGP->fingerprint(undef);
	is( $got, undef, 'undef fails' );
	like( $reason, qr/undef/, 'and the reason says so' );

	( $got, $reason ) = Fugu::OpenPGP->fingerprint('');
	is( $got, undef, 'an empty string fails' );

	# A header that claims more body than the bytes hold.
	my $short = chr(0x98) . chr(200) . 'abc';
	( $got, $reason ) = Fugu::OpenPGP->fingerprint($short);
	is( $got, undef, 'a truncated packet body fails' );
	like( $reason, qr/truncated/, 'and the reason says so' );
};

subtest 'fingerprint reads the new packet format' => sub {
	# The same key body in the new format must give the same
	# fingerprint: the hash writes 0x99 and the length again, so
	# the header of the file never reaches the digest.
	my $binary = Fugu::OpenPGP->decode_armor( slurp('openpgp-ed25519.asc') );
	my $length = ord substr $binary, 1, 1;
	my $body   = substr $binary, 2, $length;

	my $new_format = chr( 0xC0 | 6 ) . chr($length) . $body;

	is(
		scalar Fugu::OpenPGP->fingerprint($new_format),
		$FIXTURE{'openpgp-ed25519.asc'}{fingerprint},
		'the new packet format gives the same fingerprint'
	);
};

subtest 'wkd_hash matches the published vectors' => sub {
	# The two vectors of the Web Key Directory draft.
	is(
		scalar Fugu::OpenPGP->wkd_hash('Joe.Doe'),
		'iy9q119eutrkn8s1mk4r39qejnbu3n5q',
		'Joe.Doe gives the published hash'
	);
	is(
		scalar Fugu::OpenPGP->wkd_hash('bernhard.reiter'),
		'it5sewh54rxz33fwmr8u6dy4bbz8itz4',
		'bernhard.reiter gives the published hash'
	);

	# The method lowercases the part itself, so the case of the
	# input never changes the publication path.
	is(
		scalar Fugu::OpenPGP->wkd_hash('joe.doe'),
		scalar Fugu::OpenPGP->wkd_hash('JOE.DOE'),
		'the case of the local part changes nothing'
	);

	my ( $hash, $reason ) = Fugu::OpenPGP->wkd_hash('');
	is( $hash, undef, 'an empty local part fails' );
	like( $reason, qr/empty/, 'and the reason says so' );

	( $hash, $reason ) = Fugu::OpenPGP->wkd_hash(undef);
	is( $hash, undef, 'undef fails' );
	like( $reason, qr/undef/, 'and the reason says so' );
};

subtest 'zbase32 encodes each group' => sub {
	is( Fugu::OpenPGP->zbase32(''),    '', 'the empty string gives nothing' );
	is( Fugu::OpenPGP->zbase32(undef), '', 'undef gives nothing' );

	# A SHA-1 digest is 20 bytes, which is 160 bits, and 160 is a
	# multiple of 5. The hash therefore ends on a whole group, and
	# it is 32 characters.
	is( length( Fugu::OpenPGP->zbase32( "\x00" x 20 ) ),
		32, '20 bytes give 32 characters' );

	# One byte is 8 bits, so it takes two characters and the
	# second one carries three zero bits.
	is( length( Fugu::OpenPGP->zbase32("\x00") ),
		2, 'one byte gives two characters' );

	# The alphabet starts with y, so an all-zero input gives y
	# for every character. This catches a swap to the RFC 4648
	# alphabet, which would give a.
	is( Fugu::OpenPGP->zbase32( "\x00" x 5 ),
		'y' x 8, 'zero bytes give the first letter of the alphabet' );

	is( length( Fugu::OpenPGP->zbase32("\xFF") ),
		2, 'a full byte gives two characters' );
};

subtest 'decode_armor bounds the input size' => sub {
	my $huge =
	      "-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n"
	    . encode_base64( 'x' x ( 2 * 1024 * 1024 ) )
	    . "=abcd\n-----END PGP PUBLIC KEY BLOCK-----\n";

	my ( $binary, $reason ) = Fugu::OpenPGP->decode_armor($huge);
	is( $binary, undef, 'a block above the bound fails' );
	like( $reason, qr/larger than/, 'and the reason says so' );
};

done_testing();
