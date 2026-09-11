#!/usr/bin/env perl
# ex:ts=8 sw=4:

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);
use Test::More;
use File::Temp qw(tempdir);
use FindBin    qw($RealBin);
use lib "$RealBin/../../lib";

use_ok('Fugu::Signify');
use Fugu::File;
use Fugu::Process;
use MIME::Base64 qw(decode_base64 encode_base64);

my $dir = tempdir( CLEANUP => 1 );

# The fixtures of the perl engine. The operator made them once with
# signify(1) and committed them, so no test makes a key or a
# signature. Key a signed the message, and key b holds another key
# number.
my $KEY_A = "$RealBin/signify-a.pub";
my $KEY_B = "$RealBin/signify-b.pub";
my $MSG   = "$RealBin/signify-a.msg";
my $MSG_SIG = "$MSG.sig";

# write_file($path, $bytes):
#	Write a fixture file.
sub write_file ( $path, $bytes )
{
	open my $fh, '>', $path or die "Cannot write $path: $!";
	binmode $fh;
	print {$fh} $bytes;
	close $fh or die "Cannot close $path: $!";
	return $path;
}

# signify_object(@keys):
#	A verifier that takes the signify(1) engine. The default
#	engine is perl, so each test of the command names the engine.
sub signify_object (@keys)
{
	return Fugu::Signify->new( keys => \@keys, engine => 'signify' );
}

# --- the subtests that need no signify(1) ---------------------------------

subtest 'the constants hold the documented values' => sub {
	is( Fugu::Signify::MAX_MANIFEST_SIZE(),
		1_048_576, 'MAX_MANIFEST_SIZE is 1 MiB' );
	is( Fugu::Signify::SIGNIFY_TIMEOUT(), 30, 'SIGNIFY_TIMEOUT is 30' );
	is( Fugu::Signify::MAX_SIGNIFY_FILE_SIZE(),
		4096, 'MAX_SIGNIFY_FILE_SIZE is 4 KiB' );
	is( Fugu::Signify::PUBLIC_KEY_SIZE(), 42, 'PUBLIC_KEY_SIZE is 42' );
	is( Fugu::Signify::SIGNATURE_SIZE(),  74, 'SIGNATURE_SIZE is 74' );
};

subtest 'the module cannot sign' => sub {
	ok( !Fugu::Signify->can('sign'), 'no sign method exists' );
};

subtest 'new dies for a bad keys argument' => sub {
	ok( !eval { Fugu::Signify->new; 1 }, 'new dies for an absent keys' );
	like( $@, qr/keys/, 'the message names keys' );

	ok( !eval { Fugu::Signify->new( keys => 'one.pub' ); 1 },
		'new dies for a scalar keys' );
	ok( !eval { Fugu::Signify->new( keys => [] ); 1 },
		'new dies for an empty keys' );
};

subtest 'an absent command is a clean failure' => sub {
	my $sig = Fugu::Signify->new(
		keys    => ["$dir/key.pub"],
		command => '/nonexistent/signify',
	);
	ok( defined $sig, 'new returns an object' );
	is( $sig->is_available, 0,     'is_available returns 0' );
	is( $sig->command,      undef, 'command returns undef' );
	like( $sig->error, qr{/nonexistent/signify},
		'error names the reason' );

	my $key = eval { $sig->verify("$dir/file") };
	is( $@,   '',    'verify does not die' );
	is( $key, undef, 'verify returns undef' );
	is( $sig->command_absent, 1, 'command_absent returns 1' );

	my $mkey = eval {
		$sig->verify_manifest(
			manifest => "$dir/SHA256",
			files    => { 'file' => "$dir/file" },
		);
	};
	is( $@,    '',    'verify_manifest does not die' );
	is( $mkey, undef, 'verify_manifest returns undef' );
};

subtest 'verify_manifest dies for a bad argument' => sub {
	my $sig = Fugu::Signify->new(
		keys    => ["$dir/key.pub"],
		command => '/nonexistent/signify',
	);
	ok( !eval { $sig->verify_manifest( files => { a => 'b' } ); 1 },
		'verify_manifest dies for an absent manifest' );
	like( $@, qr/manifest/, 'the message names manifest' );

	ok(
		!eval {
			$sig->verify_manifest(
				manifest => "$dir/SHA256",
				files    => {},
			);
			1;
		},
		'verify_manifest dies for an empty files'
	);
	like( $@, qr/files/, 'the message names files' );
};

subtest '_parse_manifest reads the sha256(1) line form' => sub {
	my $sig = Fugu::Signify->new(
		keys    => ["$dir/key.pub"],
		command => '/nonexistent/signify',
	);
	my $hex_a = 'a' x 64;
	my $hex_b = 'b' x 64;
	my $hex_c = 'c' x 64;

	my $three = $sig->_parse_manifest( "SHA256 (one.img) = $hex_a\n"
		    . "SHA256 (two.img) = $hex_b\n"
		    . "SHA256 (three.img) = $hex_c\n" );
	is_deeply(
		$three,
		{
			'one.img'   => $hex_a,
			'two.img'   => $hex_b,
			'three.img' => $hex_c,
		},
		'three lines give three pairs'
	);

	is( $sig->_parse_manifest(''), undef, 'an empty manifest fails' );
	like( $sig->error, qr/empty/, 'the reason names the empty manifest' );

	is( $sig->_parse_manifest("one.img: $hex_a\n"),
		undef, 'an unparsed line fails' );
	like( $sig->error, qr/cannot parse/, 'the reason names the line' );

	is( $sig->_parse_manifest("SHA256 (one.img) = abc123\n"),
		undef, 'a short digest fails' );
	like( $sig->error, qr/64 hexadecimal/, 'the reason names the width' );

	is(
		$sig->_parse_manifest( "SHA256 (one.img) = $hex_a\n"
			    . "SHA256 (one.img) = $hex_b\n" ),
		undef,
		'a duplicate key fails'
	);
	like( $sig->error, qr/duplicate/, 'the reason names the duplicate' );

	# A key is opaque text. A file path and a download URL each
	# hold a solidus, and a URL holds a colon and a dot as well.
	my $mixed = $sig->_parse_manifest(
		    "SHA256 (dist/one.img) = $hex_a\n"
		    . "SHA256 (https://example.org/dl/two.img) = $hex_b\n"
		    . "SHA256 (three.img) = $hex_c\n" );
	is_deeply(
		$mixed,
		{
			'dist/one.img'                    => $hex_a,
			'https://example.org/dl/two.img'  => $hex_b,
			'three.img'                       => $hex_c,
		},
		'a path key and a URL key parse whole'
	);

	my $upper = $sig->_parse_manifest(
		'SHA256 (one.img) = ' . ( 'A' x 64 ) . "\n" );
	is_deeply( $upper, { 'one.img' => $hex_a },
		'an upper-case digest folds to lower case' );
};

subtest '_digest streams a file' => sub {
	my $path = write_file( "$dir/digest.txt", 'hello' );
	is(
		Fugu::Signify::_digest($path),
		'2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
		'_digest returns the known SHA256 of the fixed string'
	);
	is( Fugu::Signify::_digest("$dir/nonexistent"),
		undef, '_digest returns undef for a file that does not open' );
};

subtest '_find_command walks PATH' => sub {
	is( Fugu::Signify::_find_command('fugu-no-such-command-59999'),
		undef, 'a name that no PATH entry holds gives undef' );

	my $bindir = tempdir( CLEANUP => 1 );
	my $tool   = write_file( "$bindir/fugu-test-tool", "#!/bin/sh\n" );
	chmod 0755, $tool or die "Cannot chmod $tool: $!";

	local $ENV{PATH} = $bindir;
	is( Fugu::Signify::_find_command('fugu-test-tool'),
		$tool, 'a name in a temporary PATH entry gives its path' );
};

subtest 'new takes the engine option' => sub {
	my $default = Fugu::Signify->new( keys => [$KEY_A] );
	is( $default->is_available,   1,     'the perl engine can verify' );
	is( $default->command,        undef, 'and it resolves no command' );
	is( $default->command_absent, 0,     'and no command is absent' );
	is( $default->error,          undef, 'and it holds no reason' );

	# A caller that names a command asks for the command, so that
	# call takes the signify engine.
	my $named = Fugu::Signify->new(
		keys    => [$KEY_A],
		command => '/nonexistent/signify',
	);
	is( $named->is_available, 0,
		'a named command takes the signify engine' );

	ok(
		!eval {
			Fugu::Signify->new(
				keys   => [$KEY_A],
				engine => 'gpg',
			);
			1;
		},
		'new dies for an engine that the module does not hold'
	);
	like( $@, qr/engine/, 'the message names engine' );

	# The perl engine needs no command on the host at all.
	local $ENV{PATH} = '';
	my $empty = Fugu::Signify->new( keys => [$KEY_A] );
	is( $empty->is_available, 1,
		'the perl engine can verify with an empty PATH' );
};

subtest 'the parsers read a signify(1) file' => sub {
	my $sig = Fugu::Signify->new( keys => [$KEY_A] );

	my $key_a = $sig->parse_public_key( Fugu::File->read($KEY_A) );
	is( $key_a->{comment}, 'fugu test key a public key',
		'parse_public_key reads the comment' );
	is( length $key_a->{keynum}, 8,  'and the 8-byte key number' );
	is( length $key_a->{key},    32, 'and the 32-byte key' );
	is( $sig->error, undef, 'and it reports no reason' );

	my $key_b = $sig->parse_public_key( Fugu::File->read($KEY_B) );
	isnt( $key_b->{keynum}, $key_a->{keynum},
		'the two fixture keys hold two key numbers' );

	my $signature = $sig->parse_signature( Fugu::File->read($MSG_SIG) );
	is( $signature->{comment}, 'verify with signify-a.pub',
		'parse_signature reads the comment' );
	is( $signature->{keynum}, $key_a->{keynum},
		'and the key number of key a' );
	is( length $signature->{signature}, 64,
		'and the 64-byte signature' );

	my ( $comment, $body ) = split /\n/, Fugu::File->read($KEY_A);

	is( $sig->parse_public_key("$comment\n" . substr( $body, 0, 52 ) ),
		undef, 'a body of the wrong length fails' );
	like( $sig->error, qr/56 base64 characters/,
		'and the reason names the width' );

	# 56 characters that decode short, because the padding ends
	# the body one byte early.
	is( $sig->parse_public_key( "$comment\n" . substr( $body, 0, 55 ) . '=' ),
		undef, 'a body that decodes short fails' );
	like( $sig->error, qr/not 42 bytes/, 'and the reason names the size' );

	my $wrong = encode_base64(
		'Xx' . substr( decode_base64($body), 2 ), '' );
	is( $sig->parse_public_key("$comment\n$wrong"), undef,
		'a body with a wrong prefix fails' );
	like( $sig->error, qr/no Ed25519/, 'and the reason says so' );

	is( $sig->parse_public_key("$comment\n"), undef,
		'a file with one line fails' );
	like( $sig->error, qr/two lines/, 'and the reason says so' );

	is( $sig->parse_public_key("$comment\n$body\nmore\n"),
		undef, 'a file with three lines fails' );
	like( $sig->error, qr/two lines/, 'and the reason says so' );

	is( $sig->parse_public_key("comment\n$body"), undef,
		'a first line without the header fails' );
	like( $sig->error, qr/untrusted comment/, 'and the reason says so' );

	is( $sig->parse_public_key(undef), undef, 'undef fails' );
	like( $sig->error, qr/undef/, 'and the reason says so' );

	is( $sig->parse_public_key("$comment\nw\x{105}"), undef,
		'a character above 255 fails' );
	like( $sig->error, qr/above 255/, 'and the reason says so' );

	my ( $sig_comment, $sig_body ) =
	    split /\n/, Fugu::File->read($MSG_SIG);

	my $wrong_signature = encode_base64(
		'Xx' . substr( decode_base64($sig_body), 2 ), '' );
	is( $sig->parse_signature("$sig_comment\n$wrong_signature"),
		undef, 'a signature body with a wrong prefix fails' );
	like( $sig->error, qr/no Ed25519/, 'and the reason says so' );

	is( $sig->parse_signature("$sig_comment\n"), undef,
		'a signature file with one line fails' );
	like( $sig->error, qr/two lines/, 'and the reason says so' );

	# The two bodies differ in length, so neither parser reads
	# the file of the other.
	is( $sig->parse_signature( Fugu::File->read($KEY_A) ),
		undef, 'a public key is no signature' );
	like( $sig->error, qr/100 base64 characters/,
		'and the reason names the width' );
	is( $sig->parse_public_key( Fugu::File->read($MSG_SIG) ),
		undef, 'a signature is no public key' );
};

subtest 'the perl engine verifies the fixture' => sub {
	my $sig = Fugu::Signify->new( keys => [$KEY_A] );
	is( $sig->verify( $MSG, $MSG_SIG ), $KEY_A,
		'verify returns the key path' );
	is( $sig->error,          undef, 'error is undef after a success' );
	is( $sig->command_absent, 0,     'command_absent returns 0' );

	is( $sig->verify($MSG), $KEY_A,
		'and the signature path defaults to "$file.sig"' );
};

subtest 'the perl engine fails for a wrong key' => sub {
	my $sig = Fugu::Signify->new( keys => [$KEY_B] );
	is( $sig->verify( $MSG, $MSG_SIG ), undef, 'verify returns undef' );
	like( $sig->error, qr/checked against wrong key/,
		'the reason names the wrong key' );
	like( $sig->error, qr/\Q$KEY_B\E/, 'and it names the key file' );
	is( $sig->command_absent, 0, 'a wrong key is no absent command' );
};

subtest 'the perl engine fails for a changed message' => sub {
	my $changed = write_file( "$dir/changed.msg", "another body\n" );
	my $sig     = Fugu::Signify->new( keys => [$KEY_A] );
	is( $sig->verify( $changed, $MSG_SIG ), undef,
		'verify returns undef' );
	like( $sig->error, qr/signature verification failed/,
		'the reason names the failed signature' );
	like( $sig->error, qr/\Q$changed\E/, 'and it names the file' );
};

subtest 'the perl engine walks the key set in trust order' => sub {
	my $sig = Fugu::Signify->new( keys => [ $KEY_B, $KEY_A ] );
	is( $sig->verify( $MSG, $MSG_SIG ), $KEY_A,
		'the second key verifies, and verify returns its path' );
	is( $sig->error, undef,
		'and the reason of the first key does not survive' );
};

subtest 'the perl engine fails closed on a file' => sub {
	my $sig = Fugu::Signify->new( keys => [$KEY_A] );

	is( $sig->verify( "$dir/absent.msg", $MSG_SIG ),
		undef, 'an absent message file fails' );
	like( $sig->error, qr{\Q$dir/absent.msg\E}, 'and it names the path' );

	is( $sig->verify( $MSG, "$dir/absent.sig" ),
		undef, 'an absent signature file fails' );
	like( $sig->error, qr{\Q$dir/absent.sig\E}, 'and it names the path' );

	my $big = write_file( "$dir/big.sig",
		'x' x ( Fugu::Signify::MAX_SIGNIFY_FILE_SIZE() + 1 ) );
	is( $sig->verify( $MSG, $big ), undef,
		'a signature file above the bound fails' );
	like( $sig->error, qr/under 4096 bytes/,
		'and the reason names the bound' );

	# A malformed signature file must give the shape that both
	# engines write: the file, then each key with its reason.
	my $malformed = write_file( "$dir/malformed.sig", "one line\n" );
	is( $sig->verify( $MSG, $malformed ),
		undef, 'a malformed signature file fails' );
	is(
		$sig->error,
		"$MSG: no key verified the signature:\n"
		    . "    $KEY_A: a signify file holds two lines",
		'and the reason holds the shape of both engines'
	);

	my $absent = Fugu::Signify->new( keys => ["$dir/absent.pub"] );
	is( $absent->verify( $MSG, $MSG_SIG ),
		undef, 'a key file that does not open fails' );
	like( $absent->error, qr/cannot read a signify file/,
		'and the reason names that key' );
};

subtest 'verify_manifest serves the perl engine' => sub {

	# The fixture message is no manifest, so verify_manifest must
	# pass the signature and then fail in the parser. The reason
	# proves that the perl engine served the method.
	my $sig = Fugu::Signify->new( keys => [$KEY_A] );
	is(
		$sig->verify_manifest(
			manifest => $MSG,
			files    => { 'one.img' => $MSG },
		),
		undef,
		'verify_manifest returns undef'
	);
	like( $sig->error, qr/cannot parse manifest line/,
		'and the reason is the manifest form, not the signature' );
};

# --- the subtests that need signify(1) ------------------------------------

my $signify = Fugu::Signify::_find_command();

# sign($seckey, $file, $sigfile):
#	Sign a fixture with signify(1) itself. The module never signs,
#	so the test drives the command directly for the setup.
sub sign ( $seckey, $file, $sigfile = undef )
{
	$sigfile //= "$file.sig";
	my $result = Fugu::Process->run(
		cmd => [
			$signify, '-S', '-s', $seckey,
			'-m', $file, '-x', $sigfile,
		] );
	die "Cannot sign $file: $result->{stderr}" unless $result->{success};
	return $sigfile;
}

# manifest_line($key, $path):
#	One sha256(1) line. The key is the text between the
#	parentheses, and it needs no relation to $path.
sub manifest_line ( $key, $path )
{
	my $hex = Fugu::Signify::_digest($path)
	    or die "Cannot digest $path";
	return "SHA256 ($key) = $hex\n";
}

my ( $pub_a, $sec_a, $pub_b, $sec_b );
my ( $message, $sigfile, $manifest );

# A download URL as a manifest key. It holds a colon, a solidus and a
# dot, and the parser must take it whole.
my $URL_KEY = 'https://example.org/dl/two.img';

if ( defined $signify ) {

	# Two throwaway key pairs: a real signature, a real second
	# key, and a real wrong-key case.
	( $pub_a, $sec_a ) = ( "$dir/a.pub", "$dir/a.sec" );
	( $pub_b, $sec_b ) = ( "$dir/b.pub", "$dir/b.sec" );
	for my $pair ( [ $pub_a, $sec_a ], [ $pub_b, $sec_b ] ) {
		my $result = Fugu::Process->run(
			cmd => [
				$signify, '-G', '-n',
				'-p', $pair->[0], '-s', $pair->[1],
			] );
		die "Cannot generate $pair->[0]: $result->{stderr}"
		    unless $result->{success};
	}

	$message = write_file( "$dir/message.txt", "the fixture body\n" );
	$sigfile = sign( $sec_a, $message );

	write_file( "$dir/one.img", 'payload one' );
	write_file( "$dir/two.img", 'payload two' );

	# A key is opaque, so the fixture holds a bare name, a path
	# and a URL. Each one must reach the same comparison.
	$manifest = write_file( "$dir/SHA256",
		    manifest_line( 'one.img', "$dir/one.img" )
		    . manifest_line( 'two.img', "$dir/two.img" )
		    . manifest_line( 'dist/two.img', "$dir/two.img" )
		    . manifest_line( $URL_KEY, "$dir/two.img" ) );
	sign( $sec_a, $manifest );
}

subtest 'verify returns the key for a good signature' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $sig = signify_object($pub_a);
	is( $sig->verify( $message, $sigfile ),
		$pub_a, 'verify returns the key path' );
	is( $sig->error,          undef, 'error is undef after a success' );
	is( $sig->command_absent, 0,     'command_absent returns 0' );
};

subtest 'verify fails for a tampered message' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $tampered = write_file( "$dir/tampered.txt", "another body\n" );
	my $sig      = signify_object($pub_a);
	is( $sig->verify( $tampered, $sigfile ),
		undef, 'verify returns undef' );
	like( $sig->error, qr/\Q$tampered\E/, 'error names the file' );
};

subtest 'verify fails for a wrong key' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $sig = signify_object($pub_b);
	is( $sig->verify( $message, $sigfile ),
		undef, 'verify returns undef' );
	is( $sig->command_absent, 0, 'a wrong key is not an absent command' );
	like( $sig->error, qr/\Q$pub_b\E/, 'error names the key' );
};

subtest 'verify walks the key set in order' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $second = write_file( "$dir/second.txt", "the second body\n" );
	sign( $sec_b, $second );

	my $sig = signify_object( $pub_a, $pub_b );
	is( $sig->verify($second), $pub_b,
		'verify returns the second key when the second key signed' );
};

subtest 'verify fails for an absent message file' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $sig = signify_object($pub_a);
	is( $sig->verify( "$dir/absent.txt", $sigfile ),
		undef, 'verify returns undef' );
	like( $sig->error, qr{\Q$dir/absent.txt\E}, 'error names the path' );
};

subtest 'verify fails for an absent signature file' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $sig = signify_object($pub_a);
	is( $sig->verify( $message, "$dir/absent.sig" ),
		undef, 'verify returns undef' );
	like( $sig->error, qr{\Q$dir/absent.sig\E}, 'error names the path' );
};

subtest 'verify defaults the signature path to $file.sig' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $sig = signify_object($pub_a);
	is( $sig->verify($message), $pub_a,
		'verify uses "$file.sig" with no signature path' );
};

subtest 'verify_manifest passes a good manifest and file' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $sig = signify_object($pub_a);
	my $key = $sig->verify_manifest(
		manifest => $manifest,
		files    => { 'one.img' => "$dir/one.img" },
	);
	is( $key, $pub_a, 'verify_manifest returns the key path' );
};

subtest 'verify_manifest fails on a digest mismatch' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $changed = write_file( "$dir/changed.img", 'another payload' );
	my $sig     = signify_object($pub_a);
	is(
		$sig->verify_manifest(
			manifest => $manifest,
			files    => { 'one.img' => $changed },
		),
		undef,
		'verify_manifest returns undef'
	);
	like( $sig->error, qr/one\.img/, 'error names the file' );
	like( $sig->error, qr/mismatch/, 'error names the mismatch' );
};

subtest 'verify_manifest fails for a name the manifest does not hold' =>
    sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $sig = signify_object($pub_a);
	is(
		$sig->verify_manifest(
			manifest => $manifest,
			files    => { 'ghost.img' => "$dir/one.img" },
		),
		undef,
		'verify_manifest returns undef'
	);
	like( $sig->error, qr/ghost\.img/, 'error names the name' );
    };

subtest 'verify_manifest fails for a local file that does not open' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $sig = signify_object($pub_a);
	is(
		$sig->verify_manifest(
			manifest => $manifest,
			files    => { 'one.img' => "$dir/absent.img" },
		),
		undef,
		'verify_manifest returns undef'
	);
	like( $sig->error, qr{\Q$dir/absent.img\E}, 'error names the path' );
};

subtest 'verify_manifest refuses a manifest above MAX_MANIFEST_SIZE' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $big = write_file( "$dir/BIG256",
		'x' x ( Fugu::Signify::MAX_MANIFEST_SIZE() + 1 ) );
	sign( $sec_a, $big );

	my $sig = signify_object($pub_a);
	is(
		$sig->verify_manifest(
			manifest => $big,
			files    => { 'one.img' => "$dir/one.img" },
		),
		undef,
		'verify_manifest returns undef'
	);
	like( $sig->error, qr/larger than/, 'error names the bound' );
};

subtest 'verify_manifest digests no file behind a broken signature' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	# The signature is for the untouched manifest, so the copy
	# with one more line has a broken signature.
	my $broken = write_file(
		"$dir/BROKEN256",
		Fugu::File->read($manifest)
		    . manifest_line( 'three.img', "$dir/one.img" ) );
	write_file( "$dir/BROKEN256.sig",
		Fugu::File->read("$manifest.sig") );

	# An unreadable local file proves that no digest ran: a digest
	# of it would flip the reason away from the signature.
	my $sig = signify_object($pub_a);
	is(
		$sig->verify_manifest(
			manifest => "$dir/BROKEN256",
			files    => { 'one.img' => "$dir/absent.img" },
		),
		undef,
		'verify_manifest returns undef'
	);
	like( $sig->error, qr/no key verified/,
		'the reason is the signature, not a digest' );
};

subtest 'verify_manifest accepts a key that differs from the path' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $moved = write_file( "$dir/moved.tmp",
		Fugu::File->read("$dir/two.img") );
	my $sig = signify_object($pub_a);
	is(
		$sig->verify_manifest(
			manifest => $manifest,
			files    => { 'two.img' => $moved },
		),
		$pub_a,
		'the manifest key maps to the local path'
	);
};

subtest 'verify_manifest takes a path key and a URL key' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	# The caller decides where the bytes sit, so neither key needs
	# to name a path that exists.
	my $sig = signify_object($pub_a);
	is(
		$sig->verify_manifest(
			manifest => $manifest,
			files    => {
				'dist/two.img' => "$dir/two.img",
				$URL_KEY       => "$dir/two.img",
			},
		),
		$pub_a,
		'both keys verify against one local file'
	);

	my $tampered = write_file( "$dir/tampered.img", 'payload three' );
	is(
		$sig->verify_manifest(
			manifest => $manifest,
			files    => { $URL_KEY => $tampered },
		),
		undef,
		'and a URL key still catches a digest mismatch'
	);
	like( $sig->error, qr/\Q$URL_KEY\E: digest mismatch/,
		'the reason names the URL key' );

	is(
		$sig->verify_manifest(
			manifest => $manifest,
			files => { 'https://other.example/x' => "$dir/two.img" },
		),
		undef,
		'a key that the manifest does not hold fails'
	);
	like( $sig->error, qr/does not hold/, 'and the reason says so' );
};

subtest 'both engines give one answer on the fixture' => sub {
	plan skip_all => 'signify(1) not available' unless defined $signify;

	my $changed = write_file( "$dir/both.msg", "a different body\n" );

	for my $case ( [ $MSG, $KEY_A ], [ $changed, undef ] ) {
		my ( $file, $expected ) = @$case;

		for my $engine (qw(perl signify)) {
			my $sig = Fugu::Signify->new(
				keys   => [$KEY_A],
				engine => $engine,
			);
			is( $sig->verify( $file, $MSG_SIG ),
				$expected, "the $engine engine answers for $file" );
		}
	}
};

subtest 'parse_manifest is the public form of the parser' => sub {
	my $sig = Fugu::Signify->new( keys => ["$dir/absent.pub"] );

	my $text = "SHA256 (a.img) = " . ( 'a' x 64 ) . "\n"
	    . 'SHA256 (dist/b.img) = ' . ( 'B' x 64 ) . "\n"
	    . 'SHA256 (https://example.org/c.img) = ' . ( 'c' x 64 ) . "\n";

	my $digests = $sig->parse_manifest($text);
	is_deeply(
		$digests,
		{
			'a.img'                       => 'a' x 64,
			'dist/b.img'                  => 'b' x 64,
			'https://example.org/c.img'   => 'c' x 64,
		},
		'a name, a path and a URL each read as one key'
	);
	is( $sig->error, undef, 'and the parser reports no reason' );

	# The parser needs no signify(1): a rotation reads the file it
	# wrote, and a site build cannot sign. An object with a
	# command that does not exist must still parse.
	my $no_command = Fugu::Signify->new(
		keys    => ["$dir/absent.pub"],
		command => "$dir/no-such-signify",
	);
	ok( !$no_command->is_available, 'the object resolved no command' );
	is_deeply( $no_command->parse_manifest($text), $digests,
		'and the parser still answered' );

	is( $sig->parse_manifest(''), undef, 'an empty manifest fails' );
	like( $sig->error, qr/empty/, 'and the reason says so' );

	is( $sig->parse_manifest(undef), undef, 'undef fails' );
	like( $sig->error, qr/undef/, 'and the reason says so' );

	is( $sig->parse_manifest("nonsense\n"), undef, 'a bad line fails' );
	like( $sig->error, qr/cannot parse manifest line/,
		'and the reason quotes the line' );

	is( $sig->parse_manifest("SHA256 (a.img) = abc\n"),
		undef, 'a short digest fails' );
	like( $sig->error, qr/not 64 hexadecimal/, 'and the reason says so' );

	my $twice = "SHA256 (a.img) = " . ( 'a' x 64 ) . "\n"
	    . 'SHA256 (a.img) = ' . ( 'b' x 64 ) . "\n";
	is( $sig->parse_manifest($twice), undef, 'a duplicate key fails' );
	like( $sig->error, qr/duplicate manifest key/, 'and the reason says so' );
};

subtest 'write_manifest writes the line form' => sub {
	my $sig = Fugu::Signify->new( keys => ["$dir/absent.pub"] );

	# The keys sort in ascending order, so two runs of a rotation
	# write one byte sequence.
	my $text = $sig->write_manifest(
		{
			'c.img' => 'C' x 64,
			'a.img' => 'a' x 64,
			'b.img' => 'b' x 64,
		}
	);
	is(
		$text,
		"SHA256 (a.img) = " . ( 'a' x 64 ) . "\n"
		    . 'SHA256 (b.img) = ' . ( 'b' x 64 ) . "\n"
		    . 'SHA256 (c.img) = ' . ( 'c' x 64 ) . "\n",
		'the output sorts by key, and it lowercases each digest'
	);

	# The round trip is the contract that the rotation needs: the
	# writer and the parser must agree on the line form.
	my %digests = (
		'a.img'                     => 'a' x 64,
		'dist/b.img'                => 'b' x 64,
		'https://example.org/c.img' => 'c' x 64,
	);
	is_deeply( $sig->parse_manifest( $sig->write_manifest( \%digests ) ),
		\%digests, 'write_manifest then parse_manifest round trips' );

	is( $sig->write_manifest( {} ), undef, 'an empty digest set fails' );
	like( $sig->error, qr/empty/, 'and the reason says so' );

	# parse_manifest reads a key with a parenthesis back without a
	# change, because it takes the text up to the last one. The
	# writer rejects such a key for a stricter reader: sha256(1)
	# and scripts/deps both read a manifest.
	is( $sig->write_manifest( { 'a(1).img' => 'a' x 64 } ),
		undef, 'a key with a parenthesis fails' );
	like( $sig->error, qr/parenthesis/, 'and the reason says so' );

	is( $sig->write_manifest( { 'a b.img' => 'a' x 64 } ),
		undef, 'a key with a space fails' );
	like( $sig->error, qr/whitespace/, 'and the reason says so' );

	# The whitespace class must name the ASCII whitespace only.
	# \s reads a byte above 127 as Latin-1 under the feature set
	# of the module, so it matches U+0085 and U+00A0. A release
	# asset whose name holds a letter such as a-ogonek is valid,
	# and a rotation must not stall on it.
	my $utf8      = "w\xc4\x85z.tar.gz";
	my $utf8_text = $sig->write_manifest( { $utf8 => 'a' x 64 } );
	ok( defined $utf8_text, 'a UTF-8 key with no ASCII space passes' )
	    or diag( $sig->error );
	is_deeply( $sig->parse_manifest($utf8_text), { $utf8 => 'a' x 64 },
		'and it round trips' );

	# The bytes that only Latin-1 reads as whitespace must pass.
	for my $byte ( "\x85", "\xA0" ) {
		ok(
			defined $sig->write_manifest(
				{ "a${byte}b.img" => 'a' x 64 }
			),
			sprintf 'a key with the byte %02x passes', ord $byte
		);
	}

	is( $sig->write_manifest( { '' => 'a' x 64 } ),
		undef, 'an empty key fails' );

	is( $sig->write_manifest( { 'a.img' => 'abc' } ),
		undef, 'a short digest fails' );
	like( $sig->error, qr/not 64 hexadecimal/, 'and the reason says so' );

	is( $sig->write_manifest( { 'a.img' => 'z' x 64 } ),
		undef, 'a non-hexadecimal digest fails' );

	is( $sig->write_manifest( { 'a.img' => undef } ),
		undef, 'an undef digest fails' );

	ok( !eval { $sig->write_manifest('not a reference'); 1 },
		'a non-reference dies' );

	# A manifest is bytes. A key in character form would reach the
	# file as its UTF-8 form, so the bytes on disk would differ
	# from the key that the caller passed, and the manifest would
	# name a file that no reader finds. Perl also warns on the
	# print.
	is( $sig->write_manifest( { "w\x{105}.tar.gz" => 'a' x 64 } ),
		undef, 'a key with a character above 255 fails' );
	like( $sig->error, qr/above 255/, 'and the reason says so' );

	is( $sig->parse_manifest("SHA256 (w\x{105}) = " . ( 'a' x 64 )),
		undef, 'a manifest in character form fails' );
	like( $sig->error, qr/above 255/, 'and the reason says so' );

	# The byte form of the same name still passes.
	ok(
		defined $sig->write_manifest(
			{ "w\xc4\x85z.tar.gz" => 'a' x 64 }
		),
		'the byte form of the same name passes'
	);
};

done_testing();
