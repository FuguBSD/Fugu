#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Guards for Fugu::X509
#
# The test makes its own certificates with openssl(1), because a
# committed certificate expires and the tree then fails on a date.
# The reader subtests that need a certificate skip with the command,
# and each subtest that reads a PEM block or a DER element builds its
# own bytes and runs everywhere.
#
# Each assertion over a real certificate reads the answer of
# openssl(1) itself, so no assertion rests on the module that it
# checks. The two validity subtests read the days that the generator
# took: openssl(1) writes notBefore at the current second and
# notAfter that many days later, so the difference of the two answers
# is an exact number.

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);
use Test::More;
use File::Temp   qw(tempdir);
use MIME::Base64 qw(encode_base64);
use Digest::SHA  ();
use FindBin      qw($RealBin);
use lib "$RealBin/../../lib";

use_ok('Fugu::X509');
use Fugu::Process;

my $WORK = tempdir( 'fugu-x509-XXXXXXXX', TMPDIR => 1, CLEANUP => 1 );

# The subject of every certificate that this test makes. The four
# attributes cover the types that a code signing certificate holds,
# and the values hold a space, so the reader must keep one.
my $SUBJECT = '/C=SE/O=Fugu Example/OU=Fugu Team/CN=Fugu Test';
my %EXPECTED = (
	C  => 'SE',
	O  => 'Fugu Example',
	OU => 'Fugu Team',
	CN => 'Fugu Test',
);

# The first second of 2050, in UTC. RFC 5280 holds a certificate that
# expires then or later to a GeneralizedTime, so a notAfter above
# this bound proves the second time form.
use constant YEAR_2050 => 2_524_608_000;

my $openssl = Fugu::X509::_find_command();

# pem_block($type, $bytes):
#	A PEM block of the type over the bytes. The block-rule
#	subtests need no certificate, so they build their own body.
sub pem_block ( $type, $bytes )
{
	return "-----BEGIN $type-----\n"
	    . encode_base64( $bytes, "\n" )
	    . "-----END $type-----\n";
}

# write_file($path, $bytes):
#	Write a fixture file, and answer the path.
sub write_file ( $path, $bytes )
{
	open my $fh, '>', $path or die "Cannot write $path: $!";
	binmode $fh;
	print {$fh} $bytes;
	close $fh or die "Cannot close $path: $!";

	return $path;
}

# slurp($path):
#	The bytes of a file.
sub slurp ($path)
{
	open my $fh, '<', $path or die "Cannot read $path: $!";
	binmode $fh;
	local $/ = undef;
	my $bytes = <$fh>;
	close $fh;

	return $bytes;
}

# openssl(@args):
#	Run openssl(1) and answer the standard output. The check
#	drives the command directly, so no assertion rests on the
#	module that it checks.
sub openssl (@args)
{
	my $result = Fugu::Process->run(
		cmd     => [ $openssl, @args ],
		timeout => 120,
		env     => { PATH => $ENV{PATH} // '', LC_ALL => 'C' },
	);
	die "openssl @args: $result->{stderr}" unless $result->{success};

	return $result->{stdout};
}

# make_certificate($stem, $days):
#	A self-signed certificate and its private key, as two paths.
#	The pair carries no passphrase, and it dies with the work
#	directory of this test.
sub make_certificate ( $stem, $days )
{
	my $certificate = "$WORK/$stem.pem";
	my $secret      = "$WORK/$stem.key";

	openssl(
		'req',    '-x509',
		'-newkey', 'rsa:2048',
		'-nodes', '-days',
		$days,    '-subj',
		$SUBJECT, '-keyout',
		$secret,  '-out',
		$certificate
	);

	return ( $certificate, $secret );
}

# --- the byte reader ------------------------------------------------------

subtest 'the reader needs bytes, and says so' => sub {

	# Digest::SHA dies on a string that holds a code point above
	# 255, and a byte read takes the low byte of each character.
	# The contract is a clean failure, so each method tests it.
	my $wide = "\x{263A}";

	my ( $der, $pem_reason ) = Fugu::X509->decode_pem($wide);
	is( $der, undef, 'decode_pem answers undef for a wide string' );
	like( $pem_reason, qr/above 255/, 'and the reason says so' );

	my ( $hex, $hex_reason ) = Fugu::X509->fingerprint($wide);
	is( $hex, undef, 'fingerprint answers undef for a wide string' );
	like( $hex_reason, qr/above 255/, 'and the reason says so' );

	my ( $parsed, $parse_reason ) = Fugu::X509->parse($wide);
	is( $parsed, undef, 'parse answers undef for a wide string' );
	like( $parse_reason, qr/above 255/, 'and the reason says so' );

	for my $method (qw(decode_pem fingerprint parse)) {
		my ( $answer, $reason ) = Fugu::X509->$method(undef);
		is( $answer, undef, "$method answers undef for undef" );
		like( $reason, qr/undef/, 'and the reason says so' );
	}
};

subtest 'decode_pem answers the body of one CERTIFICATE block' => sub {
	my $bytes = join '', map { chr } 0 .. 255;

	my ( $der, $reason ) =
	    Fugu::X509->decode_pem( pem_block( 'CERTIFICATE', $bytes ) );
	is( $der,    $bytes, 'the block decodes to its bytes' );
	is( $reason, undef,  'and it reports no reason' );
};

subtest 'decode_pem takes one CERTIFICATE block and no other' => sub {
	my $certificate = pem_block( 'CERTIFICATE', 'the certificate' );
	my $secret      = pem_block( 'PRIVATE KEY', 'the private key' );

	# A key directory publishes what this method accepts, so a
	# private key block must never decode as a certificate.
	my ( $alone, $alone_reason ) = Fugu::X509->decode_pem($secret);
	is( $alone, undef, 'a private key block alone fails' );
	like( $alone_reason, qr/PRIVATE KEY block/,
		'and the reason names the block type' );

	my ( $both, $both_reason ) =
	    Fugu::X509->decode_pem( $certificate . $secret );
	is( $both, undef, 'a certificate with its private key fails' );
	like( $both_reason, qr/PRIVATE KEY block/,
		'and the reason names the private key' );

	my ( $two, $two_reason ) =
	    Fugu::X509->decode_pem( $certificate . $certificate );
	is( $two, undef, 'a second certificate block fails' );
	like( $two_reason, qr/2 CERTIFICATE blocks/,
		'and the reason counts the blocks' );

	my ( $none, $none_reason ) = Fugu::X509->decode_pem("no block here\n");
	is( $none, undef, 'a text with no block fails' );
	like( $none_reason, qr/no BEGIN CERTIFICATE/,
		'and the reason names the missing line' );

	my $truncated = $certificate;
	$truncated =~ s/^-----END.*\n//m;
	my ( $end, $end_reason ) = Fugu::X509->decode_pem($truncated);
	is( $end, undef, 'a block with no END line fails' );
	like( $end_reason, qr/no END CERTIFICATE/,
		'and the reason names the missing line' );
};

subtest 'decode_pem holds the body to the base64 alphabet' => sub {

	# MIME::Base64 skips a character that no alphabet holds, so a
	# body of the right character count with one bad character
	# decodes to a shorter certificate. The method must catch that
	# itself: a PEM block holds no checksum line.
	my @case = (
		[ 'a character of no alphabet', 'QU*D', qr/no base64 text/ ],
		[ 'a part of a group',          'QUJ',  qr/whole number of/ ],
		[
			'padding before the end', "QQ==\nQUJD",
			qr/padding sits before the end/
		],
	);

	for my $case (@case) {
		my ( $label, $body, $expected ) = @$case;
		my $text =
		    "-----BEGIN CERTIFICATE-----\n$body\n"
		    . "-----END CERTIFICATE-----\n";
		my ( $der, $reason ) = Fugu::X509->decode_pem($text);
		is( $der, undef, "a body with $label fails" )
		    or next;
		like( $reason, $expected, 'and the reason says why' );
	}

	my ( $empty, $empty_reason ) = Fugu::X509->decode_pem(
		"-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n");
	is( $empty, undef, 'a block with no body fails' );
	like( $empty_reason, qr/no text between/,
		'and the reason says so' );
};

subtest 'decode_pem reads either line ending and a padded line' => sub {
	my $bytes = 'the certificate bytes';
	my $text  = pem_block( 'CERTIFICATE', $bytes );

	my $crlf = $text =~ s/\n/\r\n/gr;
	is( scalar Fugu::X509->decode_pem($crlf),
		$bytes, 'a block with CRLF gives the same bytes' );

	# A mailer pads a line with a space or a tab.
	my $padded = $text =~ s/\n/ \t\n/gr;
	is( scalar Fugu::X509->decode_pem($padded),
		$bytes, 'a padded block gives the same bytes' );

	my $copy = $text;
	Fugu::X509->decode_pem($copy);
	is( $copy, $text, 'the method never changes the string of the caller' );
};

subtest 'decode_pem bounds the input size' => sub {
	my $huge =
	      "-----BEGIN CERTIFICATE-----\n"
	    . encode_base64( 'x' x ( 2 * 1024 * 1024 ), "\n" )
	    . "-----END CERTIFICATE-----\n";

	my ( $der, $reason ) = Fugu::X509->decode_pem($huge);
	is( $der, undef, 'a text above the bound fails' );
	like( $reason, qr/larger than/, 'and the reason says so' );
};

subtest 'fingerprint answers the upper-case SHA-256 of the bytes' => sub {
	my $bytes = 'the certificate bytes';

	my ( $hex, $reason ) = Fugu::X509->fingerprint($bytes);
	is( $hex, uc Digest::SHA::sha256_hex($bytes),
		'the answer is the SHA-256 in upper case' );
	is( $reason, undef, 'and it reports no reason' );
	like( $hex, qr/\A[0-9A-F]{64}\z/,
		'and it holds 64 hexadecimal characters with no separator' );
};

subtest 'parse rejects bytes that hold no certificate' => sub {
	my %case = (
		''     => qr/holds no tag/,
		"\x30" => qr/holds no tag/,

		# A SEQUENCE that names 10 content bytes and holds 3.
		"\x30\x0A\x02\x01\x01" => qr/content is truncated/,

		# A SET where the certificate stands.
		"\x31\x03\x02\x01\x01" => qr/tag 0x31, and not 0x30/,

		# The indefinite length of BER, which DER never writes.
		"\x30\x80\x02\x01\x01\x00\x00" => qr/indefinite length/,

		# A multi-byte tag, which a certificate never holds.
		"\x3F\x81\x00\x02\x01\x01" => qr/multi-byte tag/,

		# A whole SEQUENCE with one byte after it.
		"\x30\x03\x02\x01\x01\x00" => qr/bytes follow the certificate/,

		# A certificate holds a tbsCertificate first.
		"\x30\x03\x02\x01\x01" => qr/tbsCertificate: tag 0x02/,
	);

	for my $der ( sort keys %case ) {
		my ( $parsed, $reason ) = Fugu::X509->parse($der);
		is( $parsed, undef,
			sprintf 'the DER %s fails', unpack 'H*', $der )
		    or next;
		like( $reason, $case{$der}, 'and the reason says why' );
	}
};

# --- the certificate of openssl(1) ----------------------------------------

my ( $CERT, $KEY, $MADE, $LONG, $OTHER, $OTHER_KEY, $FILE );

if ( defined $openssl ) {
	$MADE = time;
	( $CERT,  $KEY )       = make_certificate( 'cert',  30 );
	( $LONG,  undef )      = make_certificate( 'long',  10_000 );
	( $OTHER, $OTHER_KEY ) = make_certificate( 'other', 30 );
	$FILE = write_file( "$WORK/release.txt", "the release bytes\n" );
}

subtest 'decode_pem and fingerprint agree with openssl(1)' => sub {
	plan skip_all => 'openssl(1) not available' unless defined $openssl;

	my $der = Fugu::X509->decode_pem( slurp($CERT) );
	ok( defined $der, 'the certificate of openssl(1) decodes' );
	is( $der, openssl( 'x509', '-in', $CERT, '-outform', 'DER' ),
		'and the bytes are the DER form of openssl(1)' );

	# "sha256 Fingerprint=A0:9E:..." holds the digest of the tool.
	my $printed =
	    openssl( 'x509', '-in', $CERT, '-noout', '-fingerprint',
		'-sha256' );
	my ($want) = $printed =~ /Fingerprint=([0-9A-Fa-f:]+)/;
	$want =~ s/://g;

	is( scalar Fugu::X509->fingerprint($der),
		uc $want, 'the fingerprint is the answer of openssl(1)' );
};

subtest 'parse reads the names and the validity' => sub {
	plan skip_all => 'openssl(1) not available' unless defined $openssl;

	my $der = Fugu::X509->decode_pem( slurp($CERT) );
	my ( $parsed, $reason ) = Fugu::X509->parse($der);
	ok( defined $parsed, 'the certificate parses' ) or diag($reason);
	is( $reason, undef, 'and it reports no reason' );

	is_deeply( $parsed->{subject}, \%EXPECTED,
		'the subject holds each attribute by its short name' );
	is_deeply( $parsed->{issuer}, \%EXPECTED,
		'and a self-signed certificate names itself as the issuer' );

	# openssl(1) writes notBefore at the current second, and
	# notAfter that many days later.
	cmp_ok( abs( $parsed->{not_before} - $MADE ),
		'<=', 300, 'notBefore names the second of the generation' );
	is( $parsed->{not_after} - $parsed->{not_before},
		30 * 86_400, 'and notAfter stands 30 days after it' );
	cmp_ok( $parsed->{not_after}, '<', YEAR_2050,
		'a certificate of 30 days takes the UTCTime form' );
};

subtest 'parse reads a GeneralizedTime' => sub {
	plan skip_all => 'openssl(1) not available' unless defined $openssl;

	# RFC 5280 holds a certificate that expires in 2050 or later
	# to the second time form, and that form writes four digits of
	# the year.
	my $der = Fugu::X509->decode_pem( slurp($LONG) );
	my $parsed = Fugu::X509->parse($der);
	ok( defined $parsed, 'the certificate parses' );
	cmp_ok( $parsed->{not_after}, '>', YEAR_2050,
		'a certificate of 10000 days expires in 2050 or later' );
	is( $parsed->{not_after} - $parsed->{not_before},
		10_000 * 86_400, 'and notAfter stands 10000 days after it' );
};

subtest 'parse rejects a damaged certificate' => sub {
	plan skip_all => 'openssl(1) not available' unless defined $openssl;

	my $der = Fugu::X509->decode_pem( slurp($CERT) );

	my ( $short, $short_reason ) =
	    Fugu::X509->parse( substr $der, 0, length($der) - 1 );
	is( $short, undef, 'a truncated certificate fails' );
	like( $short_reason, qr/truncated/, 'and the reason says so' );

	my ( $long, $long_reason ) = Fugu::X509->parse( $der . "\x00" );
	is( $long, undef, 'a certificate with one byte after it fails' );
	like( $long_reason, qr/bytes follow the certificate/,
		'and the reason says so' );

	my $flipped = $der;
	substr $flipped, 0, 1, "\x31";
	my ( $tag, $tag_reason ) = Fugu::X509->parse($flipped);
	is( $tag, undef, 'a certificate under the wrong tag fails' );
	like( $tag_reason, qr/tag 0x31, and not 0x30/,
		'and the reason names the tag' );
};

# --- the command part -----------------------------------------------------

subtest 'the object answers cleanly for an absent command' => sub {

	# An absent openssl(1) is an install problem, and new must
	# never die for one. Each command method then answers undef,
	# and it reports the absent command through command_absent.
	my $x509 = Fugu::X509->new( command => "$WORK/no-such-openssl" );

	is( $x509->is_available,   0,     'is_available answers 0' );
	is( $x509->command_absent, 1,     'command_absent answers 1' );
	is( $x509->command,        undef, 'command stays undef' );
	like( $x509->error, qr/no executable openssl command/,
		'error names the reason' );

	is(
		$x509->sign_cms(
			certificate => 'c',
			secret      => 's',
			file        => 'f'
		),
		undef,
		'sign_cms answers undef'
	);
	is(
		$x509->verify_cms(
			certificate => 'c',
			file        => 'f',
			signature   => 's'
		),
		undef,
		'verify_cms answers undef'
	);
	is( $x509->command_absent, 1, 'and command_absent still answers 1' );
};

subtest 'each command method dies for an absent argument' => sub {
	my $x509 = Fugu::X509->new;

	ok( !eval { $x509->sign_cms( secret => 's', file => 'f' ); 1 },
		'sign_cms dies for an absent certificate' );
	like( $@, qr/certificate/, 'the message names certificate' );

	ok( !eval { $x509->verify_cms( certificate => 'c', file => 'f' ); 1 },
		'verify_cms dies for an absent signature' );
	like( $@, qr/signature/, 'the message names signature' );
};

subtest 'verify_cms needs bytes, and says so' => sub {
	my $x509 = Fugu::X509->new;

	is(
		$x509->verify_cms(
			certificate => 'c',
			file        => 'f',
			signature   => "\x{263A}"
		),
		undef,
		'a wide signature answers undef'
	);
	like( $x509->error, qr/above 255/, 'and the reason says so' );
	is( $x509->command_absent, 0,
		'the command never ran, and no install problem is reported' );
};

subtest 'sign_cms and verify_cms agree' => sub {
	plan skip_all => 'openssl(1) not available' unless defined $openssl;

	my $x509 = Fugu::X509->new;
	ok( $x509->is_available, 'the object resolved openssl(1)' );
	like( $x509->command, qr/openssl/, 'and command names it' );

	my $signature = $x509->sign_cms(
		certificate => $CERT,
		secret      => $KEY,
		file        => $FILE
	);
	ok( defined $signature, 'sign_cms answers a signature' )
	    or diag( $x509->error );
	like( $signature, qr/\A-----BEGIN CMS-----\n/,
		'and the signature is a PEM block' );
	is( $x509->error, undef, 'and it reports no reason' );

	# The signature is detached: it holds the digest of the file
	# and no byte of it.
	unlike( $signature, qr/the release bytes/,
		'the signature holds no byte of the file' );

	is(
		$x509->verify_cms(
			certificate => $CERT,
			file        => $FILE,
			signature   => $signature
		),
		1,
		'verify_cms answers 1 for the signature of that file'
	);
	is( $x509->error, undef, 'and it reports no reason' );

	# openssl(1) itself must read the same signature, or the
	# module answers a form that no other tool takes.
	my $path = write_file( "$WORK/release.p7s", $signature );
	ok(
		eval {
			openssl(
				'cms',       '-verify',
				'-binary',   '-inform',
				'PEM',       '-in',
				$path,       '-content',
				$FILE,       '-certfile',
				$CERT,       '-nointern',
				'-noverify', '-out',
				'/dev/null'
			);
			1;
		},
		'and openssl(1) verifies the same signature'
	);
};

subtest 'verify_cms pins the certificate that the caller names' => sub {
	plan skip_all => 'openssl(1) not available' unless defined $openssl;

	# A CMS signature carries the certificate of its signer, so a
	# verifier that reads that copy accepts a signature of any
	# certificate. The verifier must read the one certificate of
	# the caller and no other.
	my $x509 = Fugu::X509->new;

	my $signature = $x509->sign_cms(
		certificate => $OTHER,
		secret      => $OTHER_KEY,
		file        => $FILE
	) or diag( $x509->error );

	is(
		$x509->verify_cms(
			certificate => $OTHER,
			file        => $FILE,
			signature   => $signature
		),
		1,
		'the signature verifies against its own certificate'
	);

	is(
		$x509->verify_cms(
			certificate => $CERT,
			file        => $FILE,
			signature   => $signature
		),
		undef,
		'and it fails against another certificate'
	);
	like( $x509->error, qr/signer certificate not found/,
		'the reason names the missing signer' );
	is( $x509->command_absent, 0,
		'and the failure is no install problem' );
};

subtest 'verify_cms fails for a changed file' => sub {
	plan skip_all => 'openssl(1) not available' unless defined $openssl;

	my $x509      = Fugu::X509->new;
	my $signature = $x509->sign_cms(
		certificate => $CERT,
		secret      => $KEY,
		file        => $FILE
	) or diag( $x509->error );

	my $changed = write_file( "$WORK/changed.txt", "the other bytes\n" );
	is(
		$x509->verify_cms(
			certificate => $CERT,
			file        => $changed,
			signature   => $signature
		),
		undef,
		'a signature over other bytes fails'
	);
	like( $x509->error, qr/verification failure/,
		'and the reason names the failure' );

	is(
		$x509->verify_cms(
			certificate => $CERT,
			file        => $FILE,
			signature   => "-----BEGIN CMS-----\nQUJD\n"
			    . "-----END CMS-----\n"
		),
		undef,
		'a signature that holds no CMS structure fails'
	);
	ok( length $x509->error, 'and the reason comes from openssl(1)' );
};

subtest 'sign_cms reports a failure of the command' => sub {
	plan skip_all => 'openssl(1) not available' unless defined $openssl;

	my $x509 = Fugu::X509->new;

	is(
		$x509->sign_cms(
			certificate => "$WORK/no-such.pem",
			secret      => $KEY,
			file        => $FILE
		),
		undef,
		'a certificate that no file holds fails'
	);
	like( $x509->error, qr/\Acannot sign \Q$FILE\E: /,
		'the reason names the act and the file' );
	is( $x509->command_absent, 0,
		'and the failure is no install problem' );
};

done_testing();
