# ex:ts=8 sw=4:
# $OpenBSD$
#
# Copyright (c) 2026 Dick Olsson <hi@senzilla.io>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

package Fugu::OpenPGP;

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Digest::SHA ();
use File::Path  ();
use File::Temp  ();
use Fugu::Process;
use MIME::Base64 qw(decode_base64);

# Fugu::OpenPGP - read an armored OpenPGP public key as bytes, and
# drive gpg(1) over a key.
#
# The module holds two parts. The byte reader decodes the armor of
# RFC 4880, and it computes the v4 fingerprint of a public key packet
# and the Web Key Directory hash of an email local part. It runs no
# command, and it holds class methods only, because it holds no
# state.
#
# The command part runs gpg(1) through an object. It generates a key
# with an encryption subkey, it exports both halves, it makes a
# detached signature, it verifies one, and it reads the expiry of a
# key. Each run takes a temporary home that the run removes, so no
# run reads a home of the user and no run reads an agent of the user.
#
# Every recoverable failure returns undef. A class method puts the
# reason in the second return value in list context, and an object
# method puts it in error. The module never logs: the caller decides
# what to report. A class method never dies, because a key file comes
# from outside, so bad bytes are data and not a programming error. An
# object method dies for a missing necessary argument alone.
#
# Every method that takes armored text needs bytes. Each one rejects
# a string that holds a code point above 255, because Digest::SHA
# dies on such a string and unpack 'C*' would take the low byte of
# each character.
#
# The module holds the armored secret half in memory alone. It never
# logs the half, and it writes it to no file of its own: the half
# reaches gpg(1) on the standard input.

# The CRC-24 generator polynomial and initial value of RFC 4880
# section 6.1. The armor checksum line holds this value over the
# decoded bytes.
use constant CRC24_INIT => 0x00B7_04CE;
use constant CRC24_POLY => 0x0186_4CFB;

# The z-base-32 alphabet of the Web Key Directory. It is not the
# RFC 4648 alphabet: the order differs, so the same digest gives a
# different string. A caller that swaps the alphabet publishes a key
# at a URL that gpg(1) never asks for.
use constant ZBASE32_ALPHABET => 'ybndrfg8ejkmcpqxot1uwisza345h769';

# The tag of a public key packet, per RFC 4880 section 4.3.
use constant PACKET_PUBLIC_KEY => 6;

# The largest public key packet body that a version 4 fingerprint can
# hold. The digest writes the length in two octets, per RFC 4880
# section 12.2, so a longer body has no fingerprint of this version.
use constant MAX_PACKET_BODY => 0xFFFF;

# The size bound of an armored block, 1 MiB. A public key of a person
# holds a few kilobytes. A caller that names a disk image by mistake
# gets a clean failure, not a decode of 500 MB.
use constant MAX_ARMOR_SIZE => 1_048_576;

# The time bound of one gpg(1) call, in seconds. A command that a
# caller named can be the wrong program. A key generation needs
# entropy, and it can take several seconds on an idle host.
use constant GPG_TIMEOUT => 60;

# The flags of every gpg(1) call. --batch and --no-tty hold the
# command away from a terminal, and the loopback pinentry with an
# empty passphrase holds it away from a prompt. The generator makes a
# key with no passphrase, so no half ever needs one.
use constant GPG_FLAGS => (
	'--batch',  '--no-tty',     '--quiet', '--pinentry-mode',
	'loopback', '--passphrase', '',
);

# Fugu::OpenPGP->decode_armor($text):
#	The binary form of an armored block, or undef with the reason.
#
#	The method reads the two delimiter lines and skips the armor
#	headers. It decodes the base64 body, and it compares the
#	CRC-24 checksum line against the decoded bytes.
#
#	The checksum is not decoration. A decoder that skips it
#	accepts a truncated key, and a truncated key gives a
#	fingerprint of its own.
#
#	The method returns the bytes in scalar context. In list
#	context it returns the bytes and undef on a success, and undef
#	and the reason on a failure.
sub decode_armor ( $class, $text )
{
	return _fail('the armored text is undef') unless defined $text;
	return _fail( 'the armored text holds a character above 255, '
		    . 'and this method needs bytes' )
	    if _wide($text);

	if ( length($text) > MAX_ARMOR_SIZE ) {
		return _fail(
			sprintf 'the armored text is larger than %d bytes',
			MAX_ARMOR_SIZE );
	}

	# Armor is text, so a producer can write either line ending. A
	# block that travelled through email holds CRLF. One
	# normalization here serves the delimiters and the body
	# together. The signature gives a copy, so the caller keeps
	# its own string.
	$text =~ s/\r\n/\n/g;

	# The delimiters name the block type, and both lines must name
	# the same type. A begin line of one type with an end line of
	# another is a spliced file.
	my ($type) = $text =~ /^-----BEGIN PGP ([A-Z0-9 ]+)-----[ \t]*$/m;
	return _fail('no BEGIN PGP delimiter line') unless defined $type;

	my ($end) = $text =~ /^-----END PGP ([A-Z0-9 ]+)-----[ \t]*$/m;
	return _fail('no END PGP delimiter line') unless defined $end;
	return _fail("the delimiters name two block types: $type and $end")
	    unless $type eq $end;

	my ($block) =
	    $text =~ /^-----BEGIN \QPGP $type\E-----[ \t]*\n(.*?)^-----END/ms;
	return _fail('no text between the delimiter lines')
	    unless defined $block;

	# The normalization above removed every CRLF, so no line holds
	# a trailing carriage return. A mailer that pads a line leaves
	# a space or a tab instead, and the delimiter patterns
	# tolerate the same two. The trim therefore names those two
	# and nothing else.
	#
	# \s must not stand here. Under the feature set of this file
	# it also matches 0x0B, 0x0C, 0x85 and 0xA0, and gpg(1)
	# rejects a body line that holds any of them with "invalid
	# radix64 character". A trim on \s would strip the byte and
	# accept a block that gpg(1) rejects.
	#
	# The trim touches the two ends of a line only. A line with
	# interior whitespace stays a failure, although gpg(1) reads
	# one. This method is stricter there on purpose: it validates
	# a key that a site publishes.
	my @lines = map { s/\A[ \t]+|[ \t]+\z//gr } split /\n/, $block, -1;

	# An armor header is "Key: value" or a bare "Key:", and a
	# blank line ends the header section. RFC 4880 makes that
	# blank line necessary, and gpg(1) enforces it: a block
	# without it fails with "invalid armor header". This method
	# must not accept what gpg(1) rejects, because a site would
	# then publish a key that no consumer can import.
	#
	# A header holds "Key: value" or a bare "Key:". gpg(1) reads
	# an empty value, and it rejects a value with no space after
	# the colon: "Comment:nospace" fails with "invalid armor
	# header". The pattern therefore needs the space whenever a
	# value follows. The trim above already removed a trailing
	# space, so "Key: " arrives here as "Key:".
	while ( @lines && $lines[0] =~ /\A[A-Za-z][A-Za-z0-9-]*:(?: .*)?\z/ ) {
		shift @lines;
	}

	# The trim above removed the space and the tab, so a blank
	# line is an empty line here. The test must not read \S: that
	# class treats 0x85 and 0xA0 as content on one build and not
	# on another, and a length test says the same thing on every
	# build.
	unless ( @lines && !length $lines[0] ) {
		return _fail('no blank line ends the armor header section');
	}
	shift @lines;

	# The checksum line starts with one '=' and holds four base64
	# characters. It is the last non-blank line of the body.
	my ( @body, $checksum );
	for my $line (@lines) {
		next unless length $line;
		if ( $line =~ /\A=([A-Za-z0-9+\/]{4})\z/ ) {
			return _fail('more than one checksum line')
			    if defined $checksum;
			$checksum = $1;
			next;
		}
		return _fail('a body line follows the checksum line')
		    if defined $checksum;

		# The padding of base64 ends the data, and
		# decode_base64 drops every byte after it. A line with
		# interior padding would therefore decode to a
		# truncated key, and a crafted checksum line would
		# still agree with the truncation. gpg(1) rejects such
		# a block, so this method must reject it too. The
		# padding may sit at the end of the last body line
		# only, and the loop tests that after it reads them
		# all.
		return _fail("not a base64 body line: $line")
		    unless $line =~ m{\A[A-Za-z0-9+/]+={0,2}\z};
		push @body, $line;
	}

	return _fail('no base64 body')   unless @body;
	return _fail('no checksum line') unless defined $checksum;

	# Only the last body line may carry the padding.
	for my $i ( 0 .. $#body - 1 ) {
		next unless $body[$i] =~ /=/;
		return _fail(
			      'a base64 body line before the last one holds '
			    . "padding: $body[$i]" );
	}

	# base64 carries four characters for each three bytes, so the
	# joined body must hold a whole number of groups.
	# decode_base64 drops a trailing partial group without a word.
	# One extra character would therefore give the same bytes and
	# the same checksum, and gpg(1) rejects such a block.
	my $joined = join '', @body;
	if ( length($joined) % 4 != 0 ) {
		return _fail(
			sprintf 'the base64 body holds %d characters, '
			    . 'which is not a whole number of groups',
			length $joined
		);
	}

	my $binary = decode_base64($joined);
	return _fail('the base64 body decodes to no bytes')
	    unless length $binary;

	# The pattern above fixes the checksum line at four base64
	# characters. Four characters always decode to three bytes, so
	# no length test is needed here.
	my $want = decode_base64($checksum);

	my $got = pack 'N', _crc24($binary);
	$got = substr $got, 1, 3;    # the low three bytes, big endian
	unless ( $got eq $want ) {
		return _fail(
			sprintf 'checksum mismatch: the body gives %s, '
			    . 'and the line holds %s',
			unpack( 'H*', $got ),
			unpack( 'H*', $want ) );
	}

	return wantarray ? ( $binary, undef ) : $binary;
}

# Fugu::OpenPGP->fingerprint($binary):
#	The v4 fingerprint of the first public key packet, in
#	upper-case hexadecimal with no separator, or undef with the
#	reason.
#
#	The fingerprint is the SHA-1 of the byte 0x99, the two-byte
#	length of the packet body, and that body, per RFC 4880 section
#	12.2. The constant 0x99 never changes with the packet header
#	that the file holds: a key in the new packet format gets the
#	same fingerprint as the same key in the old format. The method
#	therefore reads the length from the header and writes the
#	length again.
sub fingerprint ( $class, $binary )
{
	return _fail('the binary form is undef') unless defined $binary;
	return _fail( 'the binary form holds a character above 255, '
		    . 'and this method needs bytes' )
	    if _wide($binary);

	my ( $tag, $body, $reason ) = _first_packet($binary);
	return _fail($reason) unless defined $tag;

	return _fail("the first packet is tag $tag, and not a public key")
	    unless $tag == PACKET_PUBLIC_KEY;

	my $version = length($body) ? ord substr( $body, 0, 1 ) : undef;
	return _fail('the public key packet is empty') unless defined $version;
	return _fail("the public key packet is version $version, and not 4")
	    unless $version == 4;

	# The digest writes the body length in two octets, so a longer
	# body has no version 4 fingerprint. pack would wrap the value
	# without a warning, and the method would then answer with a
	# confident wrong fingerprint.
	if ( length($body) > MAX_PACKET_BODY ) {
		return _fail(
			sprintf 'the public key packet body is %d bytes, '
			    . 'and a version 4 fingerprint holds at most %d',
			length($body), MAX_PACKET_BODY
		);
	}

	my $hex =
	    Digest::SHA::sha1_hex( "\x99" . pack( 'n', length $body ) . $body );

	return wantarray ? ( uc $hex, undef ) : uc $hex;
}

# Fugu::OpenPGP->wkd_hash($local):
#	The Web Key Directory hash of an email local part.
#
#	The hash is the z-base-32 form of the SHA-1 of the local part
#	in lower case. gpg --locate-keys asks for
#	.well-known/openpgpkey/hu/<hash>, so the answer decides the
#	publication path. The method lowercases the part itself: the
#	draft states the rule, and a caller that lowercases twice gets
#	the same answer.
sub wkd_hash ( $class, $local )
{
	return _fail('the local part is undef') unless defined $local;
	return _fail('the local part is empty') unless length $local;
	return _fail( 'the local part holds a character above 255, '
		    . 'and this method needs bytes' )
	    if _wide($local);

	# The lowercase step must touch the ASCII letters only. lc
	# reads a byte above 127 as Latin-1 under the feature set of
	# this file, so it rewrites the bytes of a UTF-8 local part:
	# c3 becomes e3. gpg(1) lowercases the ASCII letters only, so
	# lc would publish a non-ASCII address at a path that gpg
	# never asks for.
	my $lower = $local =~ tr/A-Z/a-z/r;

	my $hash = $class->zbase32( Digest::SHA::sha1($lower) );

	return wantarray ? ( $hash, undef ) : $hash;
}

# Fugu::OpenPGP->zbase32($bytes):
#	The z-base-32 form of the bytes. The encoding writes no
#	padding, and it emits one character for each five bits. A byte
#	count that is not a multiple of five therefore ends on a
#	partial group, and the low bits of that group are zero.
sub zbase32 ( $class, $bytes )
{
	return '' unless defined $bytes && length $bytes;

	# unpack 'C*' takes the low byte of each code point, so
	# character data would give a confident wrong answer: the
	# smiling face U+263A would encode as the colon. The method
	# needs bytes, and it says so.
	return _fail( 'the input holds a character above 255, '
		    . 'and this method needs bytes' )
	    if _wide($bytes);

	my @alphabet = split //, ZBASE32_ALPHABET;
	my ( $accumulator, $bits, $out ) = ( 0, 0, '' );

	for my $byte ( unpack 'C*', $bytes ) {
		$accumulator = ( $accumulator << 8 ) | $byte;
		$bits += 8;
		while ( $bits >= 5 ) {
			$bits -= 5;
			$out .= $alphabet[ ( $accumulator >> $bits ) & 0x1F ];
		}
	}

	$out .= $alphabet[ ( $accumulator << ( 5 - $bits ) ) & 0x1F ]
	    if $bits;

	return $out;
}

# --- the command part -----------------------------------------------------

# Fugu::OpenPGP->new(%args):
#	Build a generator, a signer and a verifier over gpg(1). The
#	method resolves the command once, and it runs no process.
#
#	%args:
#		command => $command # Optional: a name or an absolute path
#
#	The method must not die for an absent command. It sets error
#	instead, and is_available then returns 0. An absent gpg(1) is
#	an install problem, and a caller reports it as one.
sub new ( $class, %args )
{
	my $self = bless {
		command_name   => $args{command},
		command        => undef,
		command_absent => 0,
		error          => undef,
	}, $class;

	my $command = _find_command( $args{command} );
	if ( defined $command ) {
		$self->{command} = $command;
	}
	else {
		$self->{error}          = _command_error( $args{command} );
		$self->{command_absent} = 1;
	}

	return $self;
}

# $self->is_available:
#	Report if the object resolved an executable gpg(1). The method
#	runs no process, and it never dies. The byte reader needs no
#	command, so a caller that reads bytes alone needs no object.
sub is_available ($self)
{
	return defined $self->{command} ? 1 : 0;
}

# $self->command:
#	The resolved command path, or undef. An operator who installed
#	the wrong gpg needs this answer in a diagnostic.
sub command ($self)
{
	return $self->{command};
}

# $self->error:
#	The reason of the most recent failure, or undef after a
#	success.
sub error ($self)
{
	return $self->{error};
}

# $self->command_absent:
#	Report if the most recent failure means that gpg(1) never ran:
#	the search list did not resolve the command, or the command
#	failed to execve(2). An absent command is an install problem,
#	and a failed signature is an integrity problem. The caller must
#	tell them apart.
sub command_absent ($self)
{
	return $self->{command_absent} ? 1 : 0;
}

# $self->generate(%args):
#	Make one Ed25519 key with one user id, and one Curve25519
#	encryption subkey. The method returns a hash reference with
#	public, secret and fingerprint, or undef with the reason in
#	error. The two halves are armored text.
#
#	%args:
#		email   => $address # Required: the user id
#		expires => $epoch   # Optional: seconds since the epoch
#
#	The user id holds the email alone. A site publishes the public
#	half, and a correspondent encrypts to the subkey.
#
#	The email reaches the user id, and an angle bracket, a line
#	ending or a NUL byte would forge a second one. The method
#	refuses each of them before the command runs, so such a call
#	makes no key.
#
#	expires is seconds since the epoch, the unit that expiry
#	answers. It must be a whole number after the current time. With
#	no expires the key and the subkey hold no expiry.
sub generate ( $self, %args )
{
	$self->{error}          = undef;
	$self->{command_absent} = 0;

	my ( $email, $expires ) = @args{qw(email expires)};
	die "email is a necessary argument\n" unless defined $email;

	return $self->_set_error('the email is empty') unless length $email;
	return $self->_set_error( 'the email holds a character above 255, '
		    . 'and this method needs bytes' )
	    if _wide($email);

	# The generator writes "<$email>" as the user id. An angle
	# bracket, a line ending or a NUL byte would close that
	# user id and open a second one, so the key would carry an
	# address that the caller never named.
	return $self->_set_error(
		'the email holds <, >, a line ending or a NUL byte')
	    if $email =~ /[<>\r\n\0]/;

	my $expire = '0';
	if ( defined $expires ) {
		return $self->_set_error(
			"the expiry $expires is not a whole number")
		    unless $expires =~ /\A-?[0-9]+\z/;
		return $self->_set_error(
			"the expiry $expires is not after the current time")
		    unless $expires > time();
		$expire = _iso_utc($expires);
	}

	$self->_command or return;

	return $self->_with_home(
		sub ($home) {
			return $self->_generate( $home, $email, $expire );
		} );
}

# $self->sign_detached(%args):
#	Sign one file with an armored secret half. The method returns
#	the armored signature, or undef with the reason in error.
#
#	%args:
#		secret => $text # Required: the armored secret half
#		file   => $path # Required: the file to sign
#
#	The secret half reaches gpg(1) on the standard input, so the
#	method writes it to no file of its own.
sub sign_detached ( $self, %args )
{
	$self->{error}          = undef;
	$self->{command_absent} = 0;

	my ( $secret, $file ) = @args{qw(secret file)};
	die "secret and file are necessary arguments\n"
	    unless defined $secret && defined $file;

	return $self->_set_error( 'the armored secret half holds a character '
		    . 'above 255, and this method needs bytes' )
	    if _wide($secret);

	$self->_command or return;

	return $self->_with_home(
		sub ($home) {
			$self->_run( $home, ['--import'],
				'cannot import the secret half', $secret )
			    or return;

			my $result = $self->_run(
				$home,
				[
					'--armor',  '--detach-sign',
					'--output', '-',
					'--',       $file
				],
				"cannot sign $file"
			) or return;

			return $result->{stdout};
		} );
}

# $self->verify_detached(%args):
#	Verify one detached signature against one armored public half.
#	The method returns 1, or undef with the reason in error.
#
#	%args:
#		public    => $text # Required: the armored public half
#		file      => $path # Required: the signed file
#		signature => $text # Required: the armored signature
#
#	The home takes the one public half of the signer, so a
#	signature of another key fails. The home of the user holds no
#	part in the answer.
sub verify_detached ( $self, %args )
{
	$self->{error}          = undef;
	$self->{command_absent} = 0;

	my ( $public, $file, $signature ) = @args{qw(public file signature)};
	die "public, file and signature are necessary arguments\n"
	    unless defined $public && defined $file && defined $signature;

	for my $pair ( [ 'public half', $public ], [ 'signature', $signature ] )
	{
		next unless _wide( $pair->[1] );
		return $self->_set_error( "the armored $pair->[0] holds a "
			    . 'character above 255, and this method needs bytes'
		);
	}

	$self->_command or return;

	return $self->_with_home(
		sub ($home) {
			$self->_run( $home, ['--import'],
				'cannot import the public half', $public )
			    or return;

			# gpg(1) reads a detached signature from a file
			# and never from the standard input, because the
			# standard input carries the signed data. The
			# signature is public, and the home holds it.
			my $sigpath = "$home/signature.asc";
			unless ( _write_file( $sigpath, $signature ) ) {
				return $self->_set_error(
					"cannot write $sigpath: $!");
			}

			$self->_run(
				$home,
				[ '--verify', '--', $sigpath, $file ],
				"cannot verify $file"
			) or return;

			return 1;
		} );
}

# $self->expiry($public):
#	The expiry of an armored public half, as seconds since the
#	epoch. The method returns 0 for a key that holds no expiry, and
#	undef with the reason in error on a failure.
#
#	The three answers differ on purpose. A caller tells "no expiry"
#	from "cannot read" with one test, and a key with no expiry
#	never reads as a key that expired.
#
#	The read imports nothing: gpg(1) shows the key and drops it, so
#	the home keeps no keyring.
sub expiry ( $self, $public )
{
	$self->{error}          = undef;
	$self->{command_absent} = 0;

	die "the armored public half is a necessary argument\n"
	    unless defined $public;

	return $self->_set_error( 'the armored public half holds a character '
		    . 'above 255, and this method needs bytes' )
	    if _wide($public);

	$self->_command or return;

	return $self->_with_home(
		sub ($home) {
			return $self->_expiry( $home, $public );
		} );
}

# $self->_generate($home, $email, $expire):
#	The body of generate, under one temporary home. The method
#	returns the hash reference of generate, or undef with the
#	reason in error.
#
#	--quick-add-key refuses an email, so the subkey needs the
#	fingerprint. The read of the fingerprint therefore sits between
#	the two generator runs, and not after the export.
sub _generate ( $self, $home, $email, $expire )
{
	$self->_run(
		$home,
		[
			'--quick-generate-key', '--',
			"<$email>",             'ed25519',
			'sign',                 $expire
		],
		"cannot generate a key for $email"
	) or return;

	my $list = $self->_run(
		$home,
		[ '--with-colons', '--list-keys' ],
		"cannot read the key of $email"
	) or return;

	my $fingerprint = _colon_field( $list->{stdout}, 'fpr', 10 );
	unless ( defined $fingerprint && length $fingerprint ) {
		return $self->_set_error(
			"cannot read the key of $email: no fingerprint line");
	}

	$self->_run(
		$home,
		[ '--quick-add-key', $fingerprint, 'cv25519', 'encr', $expire ],
		"cannot add the encryption subkey of $email"
	) or return;

	my %half;
	for my $part ( [ 'public', '--export' ],
		[ 'secret', '--export-secret-keys' ] )
	{
		my ( $name, $flag ) = @$part;
		my $result = $self->_run(
			$home,
			[ '--armor', $flag, '--', $email ],
			"cannot export the $name half of $email"
		) or return;

		# gpg(1) exits 0 with no output when it finds no key of
		# that name. An empty half is no answer, so the method
		# fails instead of handing back the empty string.
		my $text = $result->{stdout} // '';
		unless ( length $text ) {
			return $self->_set_error(
				      "cannot export the $name half of $email: "
				    . 'the export holds no key' );
		}
		$half{$name} = $text;
	}

	return {
		public      => $half{public},
		secret      => $half{secret},
		fingerprint => $fingerprint,
	};
}

# $self->_expiry($home, $public):
#	The body of expiry, under one temporary home.
#
#	The pub line of the colon form holds the creation time in field
#	6 and the expiry in field 7. An empty field 7 means that the
#	key holds no expiry.
sub _expiry ( $self, $home, $public )
{
	my $result = $self->_run(
		$home,
		[
			'--with-colons', '--import-options', 'show-only',
			'--import'
		],
		'cannot read the armored public half',
		$public
	) or return;

	my $seconds = _colon_field( $result->{stdout}, 'pub', 7 );
	unless ( defined $seconds ) {
		return $self->_set_error(
			'cannot read the armored public half: no key line');
	}

	return 0 unless length $seconds;

	unless ( $seconds =~ /\A[0-9]+\z/ ) {
		return $self->_set_error(
			      "cannot read the armored public half: "
			    . "the expiry field holds $seconds" );
	}

	return $seconds + 0;
}

# $self->_with_home($body):
#	Make a temporary gpg(1) home, run the body over it, and remove
#	the home. The method answers what the body answered.
#
#	gpg(1) writes a keyring, a trust database and an agent socket
#	under its home. A run of this module reads no home of the user,
#	so each call takes a home of its own and removes it.
#
#	The home carries a secret half, so it holds no group mode and
#	no other mode. CLEANUP is the backstop of a die, and the method
#	removes the tree itself on every other path.
#
#	The home sits under TMPDIR with a short name. The agent socket
#	sits in the home, and a unix socket path holds about 100 bytes.
sub _with_home ( $self, $body )
{
	my $home =
	    File::Temp::tempdir( 'fugu-XXXXXXXX', TMPDIR => 1, CLEANUP => 1 );

	unless ( chmod 0700, $home ) {
		my $reason = "cannot set the mode of $home: $!";
		File::Path::remove_tree($home);
		return $self->_set_error($reason);
	}

	my $answer = $body->($home);

	$self->_kill_agent($home);
	File::Path::remove_tree($home);

	return $answer;
}

# $self->_kill_agent($home):
#	Stop the gpg-agent of one temporary home. gpg 2 starts an agent
#	for a key operation, and that agent outlives a home that the
#	run removes. An agent that outlives its home leaks a process.
#
#	gpgconf(1) ships beside gpg(1), so the method names it beside
#	the resolved command. The result goes unread: an absent
#	gpgconf(1) must not fail a signature.
sub _kill_agent ( $self, $home )
{
	# _find_command answers a path that holds a solidus under every
	# input, so the substitution always names a directory.
	my $gpgconf = $self->{command} =~ s{[^/]+\z}{gpgconf}r;
	return unless -f $gpgconf && -x _;

	Fugu::Process->run(
		cmd => [ $gpgconf, '--homedir', $home, '--kill', 'gpg-agent' ],
		timeout => GPG_TIMEOUT,
		env     => _env($home),
	);

	return;
}

# $self->_run($home, $args, $what, $stdin):
#	Run one gpg(1) command under the temporary home. The method
#	returns the result of the run, or undef with the reason in
#	error. The reason starts with $what, which names the act that
#	failed.
#
#	The command is a list, so no argument needs quoting and no
#	argument can become a shell operator.
#
#	A run that never reached the child means that gpg(1) never ran,
#	so command_absent reports 1 for that call.
sub _run ( $self, $home, $args, $what, $stdin = undef )
{
	my $result = Fugu::Process->run(
		cmd =>
		    [ $self->{command}, GPG_FLAGS, '--homedir', $home, @$args ],
		timeout => GPG_TIMEOUT,
		env     => _env($home),
		( defined $stdin ? ( stdin => $stdin ) : () ),
	);

	return $result if $result->{success};

	if ( defined $result->{error} ) {
		$self->{command_absent} = 1;
		return $self->_set_error("$what: $result->{error}");
	}

	return $self->_set_error( "$what: " . _reason($result) );
}

# _env($home):
#	The environment of one gpg(1) run. The child takes this set and
#	nothing else, so no variable of the caller reaches the command.
#
#	HOME and GNUPGHOME both name the temporary home: gpg(1) reads
#	GNUPGHOME, and gpgconf(1) and the agent read either one.
#	LC_ALL holds the diagnostics in English, because _reason reads
#	them.
sub _env ($home)
{
	return {
		PATH      => $ENV{PATH} // '',
		HOME      => $home,
		GNUPGHOME => $home,
		LC_ALL    => 'C',
	};
}

# _reason($result):
#	The reason of a gpg(1) run that reached the child and failed:
#	the timeout, a line of the diagnostic without the prefix, or
#	the exit code.
#
#	The sub takes the last line that starts with "gpg: ". gpg(1)
#	writes "Signature made ..." first and the fault last, so the
#	first line names nothing. A bad signature ends with "BAD
#	signature from ...", an unknown signer ends with "Can't check
#	signature: No public key", and a text that is no key gives
#	"no valid OpenPGP data found.".
sub _reason ($result)
{
	return 'timeout after ' . GPG_TIMEOUT . ' seconds'
	    if $result->{timed_out};

	my $reason = '';
	for my $line ( split /\n/, $result->{stderr} // '' ) {
		next unless index( $line, 'gpg: ' ) == 0;
		$reason = substr $line, length 'gpg: ';
	}

	# gpg(1) pads a continuation line after the prefix.
	$reason =~ s/\A[ \t]+//;

	return length $reason ? $reason : "exit code $result->{exit_code}";
}

# _colon_field($text, $type, $number):
#	Field $number of the first record of type $type in the colon
#	form of gpg(1), or undef when the text holds no such record.
#
#	The colon form writes one record in each line, and a colon
#	separates the fields. Field 1 names the record type. The
#	fingerprint read takes field 10 of the fpr record, and the
#	expiry read takes field 7 of the pub record.
sub _colon_field ( $text, $type, $number )
{
	for my $line ( split /\n/, $text // '' ) {
		my @field = split /:/, $line, -1;
		next unless @field && $field[0] eq $type;
		return $field[ $number - 1 ];
	}

	return;
}

# _iso_utc($epoch):
#	The UTC form YYYYMMDDTHHMMSS of an epoch. gpg(1) reads that
#	form as an expiry, and the key then expires on the exact
#	second. The seconds=N form is off by one, so the generator
#	never writes it.
sub _iso_utc ($epoch)
{
	my @time = gmtime $epoch;

	return sprintf '%04d%02d%02dT%02d%02d%02d', $time[5] + 1900,
	    $time[4] + 1, $time[3], $time[2], $time[1], $time[0];
}

# _write_file($path, $text):
#	Write the text to the path, and return 1. The sub returns undef
#	with the reason in $!, and it never logs.
sub _write_file ( $path, $text )
{
	open my $fh, '>', $path or return;
	binmode $fh;
	print {$fh} $text or return;
	close $fh         or return;

	return 1;
}

# _find_command($name):
#	Resolve an executable path, or return undef. With a name that
#	holds a solidus the sub tests that path only. With a plain name
#	it walks $ENV{PATH} for that name. With no name it walks
#	$ENV{PATH} over the search list: gpg2, then gpg. A host that
#	kept gpg for version 1 carries version 2 under the name gpg2,
#	and the command part needs version 2.
sub _find_command ( $name = undef )
{
	my @names = defined $name ? ($name) : ( 'gpg2', 'gpg' );

	for my $candidate (@names) {
		if ( index( $candidate, '/' ) >= 0 ) {
			return $candidate if -f $candidate && -x _;
			next;
		}
		for my $dir ( split /:/, $ENV{PATH} // '' ) {
			next unless length $dir;
			my $path = "$dir/$candidate";
			return $path if -f $path && -x _;
		}
	}

	return;
}

# $self->_command:
#	The gpg(1) command of one call, or undef with the reason in
#	error. new resolved the command once, so the method reads that
#	answer. It sets command_absent for the call, because a command
#	that never ran is an install problem.
sub _command ($self)
{
	return $self->{command} if defined $self->{command};

	$self->{command_absent} = 1;

	return $self->_set_error( _command_error( $self->{command_name} ) );
}

# _command_error($name):
#	The reason that no gpg(1) command resolved. new and each
#	command method write one shape, so a caller reads one string.
sub _command_error ( $name = undef )
{
	my $named = $name // 'gpg2, gpg';

	return "no executable gpg command: $named";
}

# $self->_set_error($reason):
#	The failure return of every object method: the reason goes to
#	error, and the method answers undef. One helper keeps the two
#	steps in one place.
sub _set_error ( $self, $reason )
{
	$self->{error} = $reason;

	return;
}

# _first_packet($binary):
#	The tag and the body of the first packet, or undef with the
#	reason as the third value.
#
#	RFC 4880 holds two packet header formats. The old format
#	writes the tag in bits 5 to 2 and the length type in bits 1
#	and 0. The new format writes the tag in bits 5 to 0, and the
#	length in one, two or five bytes.
#
#	An armored public key of gpg(1) uses the old format. Its
#	length type is 0 for a small key and 1 for a large one. The
#	method reads both formats, because a producer chooses
#	either.
sub _first_packet ($binary)
{
	return ( undef, undef, 'the binary form holds no packet header' )
	    unless length($binary) >= 2;

	my $first = ord substr $binary, 0, 1;
	return ( undef, undef, 'the packet header has no high bit set' )
	    unless $first & 0x80;

	my ( $tag, $length, $offset );

	if ( $first & 0x40 ) {

		# The new format. One length byte below 192, two bytes
		# up to 8383, and a five-byte form for anything above.
		$tag = $first & 0x3F;
		my $first_octet = ord substr $binary, 1, 1;
		if ( $first_octet < 192 ) {
			( $length, $offset ) = ( $first_octet, 2 );
		}
		elsif ( $first_octet < 224 ) {
			return ( undef, undef,
				'the two-byte length is truncated' )
			    unless length($binary) >= 3;
			my $second = ord substr $binary, 2, 1;
			$length =
			    ( ( $first_octet - 192 ) << 8 ) + $second + 192;
			$offset = 3;
		}
		elsif ( $first_octet == 255 ) {
			return ( undef, undef,
				'the five-byte length is truncated' )
			    unless length($binary) >= 6;
			$length = unpack 'N', substr $binary, 2, 4;
			$offset = 6;
		}
		else {
			return ( undef, undef,
				'a partial body length holds no whole packet' );
		}
	}
	else {
		# The old format.
		$tag = ( $first & 0x3C ) >> 2;
		my $type = $first & 0x03;
		if ( $type == 0 ) {
			( $length, $offset ) =
			    ( ord substr( $binary, 1, 1 ), 2 );
		}
		elsif ( $type == 1 ) {
			return ( undef, undef,
				'the two-byte length is truncated' )
			    unless length($binary) >= 3;
			$length = unpack 'n', substr $binary, 1, 2;
			$offset = 3;
		}
		elsif ( $type == 2 ) {
			return ( undef, undef,
				'the four-byte length is truncated' )
			    unless length($binary) >= 5;
			$length = unpack 'N', substr $binary, 1, 4;
			$offset = 5;
		}
		else {
			return ( undef, undef,
				'an indeterminate length holds no whole packet'
			);
		}
	}

	return ( undef, undef, 'the packet body is truncated' )
	    unless length($binary) >= $offset + $length;

	return ( $tag, substr( $binary, $offset, $length ), undef );
}

# _crc24($bytes):
#	The CRC-24 of RFC 4880 section 6.1, as an integer. The armor
#	checksum line holds the low three bytes, big endian.
sub _crc24 ($bytes)
{
	my $crc = CRC24_INIT;

	for my $byte ( unpack 'C*', $bytes ) {
		$crc ^= $byte << 16;
		for ( 1 .. 8 ) {
			$crc <<= 1;
			$crc ^= CRC24_POLY if $crc & 0x0100_0000;
		}
	}

	return $crc & 0x00FF_FFFF;
}

# _wide($text):
#	True when the string holds a code point above 255. Such a
#	string is character data and not bytes. Digest::SHA dies on
#	it with "Wide character in subroutine entry", and unpack 'C*'
#	takes the low byte of each character. The contract of this
#	module is a clean failure, so every public method tests this.
#	A caller that holds text must encode it.
sub _wide ($text)
{
	return $text =~ /[^\x00-\xFF]/ ? 1 : 0;
}

# _fail($reason):
#	The failure return of every public method: undef in scalar
#	context, and undef with the reason in list context. One helper
#	keeps the two contexts in step.
sub _fail ($reason)
{
	return wantarray ? ( undef, $reason ) : undef;
}

1;
