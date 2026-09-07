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

use v5.36;

package Fugu::OpenPGP;

use Digest::SHA  ();
use MIME::Base64 qw(decode_base64);

# Fugu::OpenPGP - read an armored OpenPGP public key as bytes.
#
# The module decodes the armor of RFC 4880, it computes the v4
# fingerprint of a public key packet, and it computes the Web Key
# Directory hash of an email local part. It runs no command, so a
# caller needs no gpg(1). It holds class methods only, because it
# holds no state.
#
# Every recoverable failure returns undef, and the reason goes to the
# second return value in list context. The module never logs, and it
# never dies for bad input: a key file comes from outside, so bad
# bytes are data and not a programming error.
#
# The module reads a public key only. It holds no private key, it
# decrypts nothing, and it verifies no signature. gpg(1) owns those
# acts.

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

# The size bound of an armored block, 1 MiB. A public key of a person
# holds a few kilobytes. A caller that names a disk image by mistake
# gets a clean failure, not a decode of 500 MB.
use constant MAX_ARMOR_SIZE => 1_048_576;

# Fugu::OpenPGP->decode_armor($text):
#	The binary form of an armored block, or undef with the reason.
#
#	The method reads the two delimiter lines, it skips the armor
#	headers, it decodes the base64 body, and it compares the
#	CRC-24 checksum line against the decoded bytes. The checksum
#	is not decoration: a decoder that skips it accepts a truncated
#	key, and a truncated key gives a fingerprint of its own.
#
#	The method returns the bytes in scalar context. In list
#	context it returns the bytes and undef on a success, and undef
#	and the reason on a failure.
sub decode_armor ( $class, $text )
{
	return _fail('the armored text is undef') unless defined $text;

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

	my @lines = split /\n/, $block, -1;
	chomp @lines;
	s/\r\z// for @lines;

	# An armor header is "Key: value", and a blank line ends the
	# header section. The first line decides whether a header
	# section exists at all: the test must not ask whether the
	# block holds a blank line anywhere, because the split above
	# always leaves a trailing empty element.
	#
	# RFC 4880 writes the blank line even with no header, and
	# gpg(1) does the same. A producer that omits it holds a body
	# on the first line, and the body must still decode.
	while ( @lines && $lines[0] =~ /\A[A-Za-z][A-Za-z0-9-]*: / ) {
		shift @lines;
	}
	shift @lines if @lines && $lines[0] !~ /\S/;

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
		return _fail("not a base64 body line: $line")
		    unless $line =~ m{\A[A-Za-z0-9+/]+={0,2}\z};
		push @body, $line;
	}

	return _fail('no base64 body')   unless @body;
	return _fail('no checksum line') unless defined $checksum;

	my $binary = decode_base64( join '', @body );
	return _fail('the base64 body decodes to no bytes')
	    unless length $binary;

	my $want = decode_base64($checksum);
	return _fail('the checksum line does not decode to three bytes')
	    unless length($want) == 3;

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

	my ( $tag, $body, $reason ) = _first_packet($binary);
	return _fail($reason) unless defined $tag;

	return _fail("the first packet is tag $tag, and not a public key")
	    unless $tag == PACKET_PUBLIC_KEY;

	my $version = length($body) ? ord substr( $body, 0, 1 ) : undef;
	return _fail('the public key packet is empty') unless defined $version;
	return _fail("the public key packet is version $version, and not 4")
	    unless $version == 4;

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

	my $hash = $class->zbase32( Digest::SHA::sha1( lc $local ) );

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

# _first_packet($binary):
#	The tag and the body of the first packet, or undef with the
#	reason as the third value.
#
#	RFC 4880 holds two packet header formats. The old format
#	writes the tag in bits 5 to 2 and the length type in bits 1
#	and 0. The new format writes the tag in bits 5 to 0, and the
#	length in one, two or five bytes. An armored public key of
#	gpg(1) uses the old format, and the length type is 0 for a
#	small key and 1 for a large one. The method reads both
#	formats, because a producer chooses either.
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

# _fail($reason):
#	The failure return of every public method: undef in scalar
#	context, and undef with the reason in list context. One helper
#	keeps the two contexts in step.
sub _fail ($reason)
{
	return wantarray ? ( undef, $reason ) : undef;
}

1;
