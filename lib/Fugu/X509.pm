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

package Fugu::X509;

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Digest::SHA ();
use File::Spec  ();
use Fugu::Process;
use MIME::Base64 qw(decode_base64);

# Fugu::X509 - read an X.509 certificate as bytes, and make and
# verify a detached CMS signature with openssl(1).
#
# The module holds two parts. The byte reader decodes a PEM block,
# it computes the SHA-256 fingerprint of the DER bytes, and it reads
# the subject, the issuer and the validity from the DER itself. It
# runs no command, and it holds class methods only, because it holds
# no state. A fingerprint check and an expiry check therefore run on
# a host where openssl(1) is absent.
#
# The command part runs openssl(1) through an object. It makes a
# detached CMS signature over a file, and it verifies one against
# the one certificate that the caller names. The verifier checks no
# chain, so the caller vouches for that certificate by other means.
#
# The module holds no issuer by name. A code signing certificate of
# Apple Developer ID is one use, and the module reads every issuer
# the same way. It reads no PKCS#12 file, and it reads no extension
# of the certificate.
#
# Every recoverable failure returns undef. A class method puts the
# reason in the second return value in list context, and an object
# method puts it in error. The module never logs: the caller decides
# what to report. A class method never dies, because a certificate
# comes from outside, so bad bytes are data and not a programming
# error. An object method dies for a missing necessary argument
# alone.
#
# Every method that takes a certificate needs bytes. Each one
# rejects a string that holds a code point above 255, because
# Digest::SHA dies on such a string and a byte read takes the low
# byte of each character.

# The size bound of a PEM text, 1 MiB. A certificate holds a few
# kilobytes. A caller that names a disk image by mistake gets a
# clean failure, not a decode of 500 MB.
use constant MAX_PEM_SIZE => 1_048_576;

# The one PEM block type that the decoder takes. A key directory
# publishes what the decoder accepts, so a private key block and a
# second block are each a failure.
use constant PEM_TYPE => 'CERTIFICATE';

# The time bound of one openssl(1) call, in seconds. A command that
# a caller named can be the wrong program. A signature over a file
# of a few hundred megabytes reads the whole file.
use constant OPENSSL_TIMEOUT => 300;

# The digest of a CMS signature. The signer names it, so an old
# default of the command never decides it.
use constant SIGNATURE_DIGEST => 'sha256';

# The DER tags of the walk, per ITU-T X.690. The version of a
# certificate sits behind an explicit context tag 0, and RFC 5280
# section 4.1 holds every other field to one of these.
use constant {
	TAG_INTEGER          => 0x02,
	TAG_OID              => 0x06,
	TAG_UTC_TIME         => 0x17,
	TAG_GENERALIZED_TIME => 0x18,
	TAG_SEQUENCE         => 0x30,
	TAG_SET              => 0x31,
	TAG_VERSION          => 0xA0,
};

# The largest number of length bytes that the reader takes. Four
# bytes hold 4 GiB, and MAX_PEM_SIZE bounds a certificate long
# before that.
use constant MAX_LENGTH_BYTES => 4;

# The attribute types of a distinguished name, from the object
# identifier to the short name of openssl(1). A caller reads the
# common name and the organizational unit by name, because the
# designated requirement of Apple pins the team identifier in the
# organizational unit. An attribute type that this table does not
# hold arrives under its dotted object identifier, so the reader
# drops no attribute.
my %ATTRIBUTE_NAME = (
	'2.5.4.3'              => 'CN',
	'2.5.4.6'              => 'C',
	'2.5.4.7'              => 'L',
	'2.5.4.8'              => 'ST',
	'2.5.4.10'             => 'O',
	'2.5.4.11'             => 'OU',
	'1.2.840.113549.1.9.1' => 'emailAddress',
);

# The string forms of an attribute value, from the DER tag to the
# name of the form. RFC 5280 section 4.1.2.4 holds a name to the
# DirectoryString forms, and it names IA5String for an email
# address. Another form is a failure, and the reason names the tag.
my %STRING_TAG = (
	0x0C => 'UTF8String',
	0x13 => 'PrintableString',
	0x16 => 'IA5String',
);

# The days of each month in a common year. _month_days adds the leap
# day of February.
my @MONTH_DAYS = ( 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );

# Fugu::X509->decode_pem($text):
#	The DER bytes of a PEM certificate block, or undef with the
#	reason.
#
#	The method takes one CERTIFICATE block. It reads the two
#	delimiter lines and it decodes the base64 body. A PEM block
#	holds no checksum line, so the decoder holds the body to the
#	base64 alphabet itself: decode_base64 skips a character that
#	no alphabet holds, and a body with one bad character would
#	otherwise decode to a shorter certificate.
#
#	A private key block and a second block are each a failure,
#	because a key directory publishes what this method accepts.
#
#	The method returns the bytes in scalar context. In list
#	context it returns the bytes and undef on a success, and undef
#	and the reason on a failure.
sub decode_pem ( $class, $text )
{
	return _fail('the PEM text is undef') unless defined $text;
	return _fail( 'the PEM text holds a character above 255, '
		    . 'and this method needs bytes' )
	    if _wide($text);

	if ( length($text) > MAX_PEM_SIZE ) {
		return _fail( sprintf 'the PEM text is larger than %d bytes',
			MAX_PEM_SIZE );
	}

	# PEM is text, so a producer can write either line ending. A
	# block that travelled through email holds CRLF. The
	# substitution gives a copy, so the caller keeps its own
	# string.
	$text =~ s/\r\n/\n/g;

	my @type = $text =~ /^-----BEGIN ([A-Z0-9 ]+)-----[ \t]*$/mg;
	return _fail( 'no BEGIN ' . PEM_TYPE . ' delimiter line' )
	    unless @type;

	for my $type (@type) {
		next if $type eq PEM_TYPE;
		return _fail( "the text holds a $type block, and this "
			    . 'method takes a '
			    . PEM_TYPE
			    . ' block' );
	}

	return _fail(
		sprintf 'the text holds %d %s blocks, and this '
		    . 'method takes one',
		scalar @type,
		PEM_TYPE
	) if @type > 1;

	my $begin  = '-----BEGIN ' . PEM_TYPE . '-----';
	my $end    = '-----END ' . PEM_TYPE . '-----';
	my ($body) = $text =~ /^\Q$begin\E[ \t]*\n(.*?)^\Q$end\E[ \t]*$/ms;
	return _fail( 'no END ' . PEM_TYPE . ' delimiter line' )
	    unless defined $body;

	# A mailer pads a line with a space or a tab, and the trim
	# takes the two ends of a line. \s must not stand here: under
	# the feature set of this file it also matches 0x0B, 0x0C,
	# 0x85 and 0xA0, and openssl(1) rejects a body that holds one
	# of them.
	my @line = grep { length } map { s/\A[ \t]+|[ \t]+\z//gr }
	    split /\n/, $body, -1;
	return _fail('no text between the delimiter lines') unless @line;

	for my $line (@line) {
		return _fail("a body line is no base64 text: $line")
		    unless $line =~ m{\A[A-Za-z0-9+/]*={0,2}\z};
	}

	my $base64 = join '', @line;

	# The padding of base64 ends the data, so it sits at the end
	# of the body alone. A body with interior padding decodes to a
	# truncated certificate.
	return _fail('the base64 padding sits before the end of the body')
	    if $base64 =~ /=(?!=*\z)/;

	return _fail('the base64 body is no whole number of groups')
	    if length($base64) % 4;

	my $der = decode_base64($base64);
	return _fail('the base64 body decodes to no byte') unless length $der;

	return wantarray ? ( $der, undef ) : $der;
}

# Fugu::X509->fingerprint($der):
#	The SHA-256 of the DER bytes, in upper-case hexadecimal with
#	no separator, or undef with the reason.
#
#	openssl(1) and the tools of other vendors print the hash of a
#	leaf certificate in that form, so a caller compares two
#	strings and not two encodings. The digest covers the bytes
#	that decode_pem answered, and it reads no field of them.
sub fingerprint ( $class, $der )
{
	return _fail('the DER form is undef') unless defined $der;
	return _fail( 'the DER form holds a character above 255, '
		    . 'and this method needs bytes' )
	    if _wide($der);

	my $hex = Digest::SHA::sha256_hex($der);

	return wantarray ? ( uc $hex, undef ) : uc $hex;
}

# Fugu::X509->parse($der):
#	The names and the validity of a certificate, or undef with the
#	reason.
#
#	The method returns a hash reference with subject, issuer,
#	not_before and not_after. Each name is a hash of attribute type
#	to value, and each time is seconds since the epoch.
#
#	The method reads the DER itself and it runs no command, so a
#	fingerprint check and an expiry check run on a host where
#	openssl(1) is absent.
#
#	The walk takes the fields of RFC 5280 section 4.1 in order,
#	and it stops after the subject. It reads no extension, and it
#	reads no public key.
sub parse ( $class, $der )
{
	return _fail('the DER form is undef') unless defined $der;
	return _fail( 'the DER form holds a character above 255, '
		    . 'and this method needs bytes' )
	    if _wide($der);

	my ( $certificate, $reason ) =
	    _expect( $der, 0, TAG_SEQUENCE, 'the certificate' );
	return _fail($reason) unless defined $certificate;
	return _fail('bytes follow the certificate')
	    unless $certificate->{next} == length $der;

	my ( $tbs, $tbs_reason ) = _expect( $certificate->{content},
		0, TAG_SEQUENCE, 'the tbsCertificate' );
	return _fail($tbs_reason) unless defined $tbs;

	my $body = $tbs->{content};

	# The version sits behind an explicit context tag 0, and a
	# version 1 certificate holds none. Every other field of the
	# walk is necessary.
	my ( $version, $version_reason ) = _element( $body, 0 );
	return _fail("the tbsCertificate: $version_reason")
	    unless defined $version;

	my $offset = $version->{tag} == TAG_VERSION ? $version->{next} : 0;

	for my $field (
		[ TAG_INTEGER,  'the serial number' ],
		[ TAG_SEQUENCE, 'the signature algorithm' ] )
	{
		my ( $element, $skip_reason ) =
		    _expect( $body, $offset, @$field );
		return _fail($skip_reason) unless defined $element;
		$offset = $element->{next};
	}

	my ( $issuer, $issuer_reason ) =
	    _expect( $body, $offset, TAG_SEQUENCE, 'the issuer' );
	return _fail($issuer_reason) unless defined $issuer;

	my ( $validity, $validity_reason ) =
	    _expect( $body, $issuer->{next}, TAG_SEQUENCE, 'the validity' );
	return _fail($validity_reason) unless defined $validity;

	my ( $subject, $subject_reason ) =
	    _expect( $body, $validity->{next}, TAG_SEQUENCE, 'the subject' );
	return _fail($subject_reason) unless defined $subject;

	my %parsed;
	for my $pair ( [ issuer => $issuer ], [ subject => $subject ] ) {
		my ( $name, $name_reason ) =
		    _name( $pair->[1]{content}, "the $pair->[0]" );
		return _fail($name_reason) unless defined $name;
		$parsed{ $pair->[0] } = $name;
	}

	my $at = 0;
	for my $pair ( [ not_before => 'notBefore' ],
		[ not_after => 'notAfter' ] )
	{
		my ( $element, $element_reason ) =
		    _element( $validity->{content}, $at );
		return _fail("the validity: $element_reason")
		    unless defined $element;

		my ( $epoch, $time_reason ) =
		    _time( $element, "the $pair->[1]" );
		return _fail($time_reason) unless defined $epoch;

		$parsed{ $pair->[0] } = $epoch;
		$at = $element->{next};
	}

	return wantarray ? ( \%parsed, undef ) : \%parsed;
}

# --- the command part -----------------------------------------------------

# Fugu::X509->new(%args):
#	Build a signer and a verifier over openssl(1). The method
#	resolves the command once, and it runs no process.
#
#	%args:
#		command => $command # Optional: a name or an absolute path
#
#	The method must not die for an absent command. It sets error
#	instead, and is_available then returns 0. An absent openssl(1)
#	is an install problem, and a caller reports it as one.
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
#	Report if the object resolved an executable openssl(1). The
#	method runs no process, and it never dies. The byte reader
#	needs no command, so a caller that reads bytes alone needs no
#	object.
sub is_available ($self)
{
	return defined $self->{command} ? 1 : 0;
}

# $self->command:
#	The resolved command path, or undef. An operator who installed
#	the wrong openssl needs this answer in a diagnostic.
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
#	Report if the most recent failure means that openssl(1) never
#	ran: the search list did not resolve the command, or the
#	command failed to execve(2). An absent command is an install
#	problem, and a failed signature is an integrity problem. The
#	caller must tell them apart.
sub command_absent ($self)
{
	return $self->{command_absent} ? 1 : 0;
}

# $self->sign_cms(%args):
#	Make a detached CMS signature over one file. The method
#	returns the PEM signature, or undef with the reason in error.
#
#	%args:
#		certificate => $path # Required: the PEM certificate
#		secret      => $path # Required: the PEM private key
#		file        => $path # Required: the file to sign
#
#	The command reads the private key from the path, so no key
#	byte enters Perl and no key byte reaches a log. The caller
#	converts a PKCS#12 file with openssl pkcs12 before it names
#	the private key.
#
#	The signature is detached: it holds the digest of the file and
#	no byte of it. The verifier therefore needs the file again.
sub sign_cms ( $self, %args )
{
	$self->{error}          = undef;
	$self->{command_absent} = 0;

	my ( $certificate, $secret, $file ) =
	    @args{qw(certificate secret file)};
	die "certificate, secret and file are necessary arguments\n"
	    unless defined $certificate && defined $secret && defined $file;

	$self->_command or return;

	my $result = $self->_run( [
			'cms',            '-sign',
			'-binary',        '-md',
			SIGNATURE_DIGEST, '-signer',
			$certificate,     '-inkey',
			$secret,          '-in',
			$file,            '-outform',
			'PEM',
		],
		"cannot sign $file"
	) or return;

	return $self->_set_error(
		"cannot sign $file: the command wrote no" . ' signature' )
	    unless length $result->{stdout};

	return $result->{stdout};
}

# $self->verify_cms(%args):
#	Verify a detached CMS signature over one file. The method
#	returns 1, or undef with the reason in error.
#
#	%args:
#		certificate => $path # Required: the PEM certificate
#		file        => $path # Required: the signed file
#		signature   => $text # Required: the PEM signature
#
#	The verifier pins the one certificate that the caller names.
#	A CMS signature carries the certificate of its signer, and
#	-nointern holds the command away from it, so a signature of
#	another certificate fails. -noverify then checks no chain and
#	no revocation: the caller vouches for the certificate by other
#	means, such as the fingerprint of a key directory.
#
#	The signature reaches the command on the standard input, so
#	the method writes it to no file of its own. The command writes
#	the content of the signature to the null device, because the
#	caller holds the file already.
sub verify_cms ( $self, %args )
{
	$self->{error}          = undef;
	$self->{command_absent} = 0;

	my ( $certificate, $file, $signature ) =
	    @args{qw(certificate file signature)};
	die "certificate, file and signature are necessary arguments\n"
	    unless defined $certificate && defined $file && defined $signature;

	return $self->_set_error( 'the PEM signature holds a character above '
		    . '255, and this method needs bytes' )
	    if _wide($signature);

	$self->_command or return;

	$self->_run( [
			'cms',        '-verify',
			'-binary',    '-inform',
			'PEM',        '-content',
			$file,        '-certfile',
			$certificate, '-nointern',
			'-noverify',  '-out',
			File::Spec->devnull,
		],
		"cannot verify $file",
		$signature
	) or return;

	return 1;
}

# --- the DER reader -------------------------------------------------------

# _element($der, $offset):
#	One DER element at the offset, or undef with the reason as the
#	second value. The element holds the tag, the content and the
#	offset of the next element.
#
#	The reader takes the definite length forms alone. DER writes
#	no indefinite length, and a certificate holds no multi-byte
#	tag, so each of those is a failure.
sub _element ( $der, $offset )
{
	my $total = length $der;
	return ( undef, 'an element holds no tag and no length' )
	    unless $offset + 2 <= $total;

	my $tag = ord substr $der, $offset, 1;
	return ( undef, sprintf 'tag 0x%02X is a multi-byte tag', $tag )
	    if ( $tag & 0x1F ) == 0x1F;

	my $first = ord substr $der, $offset + 1, 1;
	my ( $length, $start );

	if ( $first < 0x80 ) {
		( $length, $start ) = ( $first, $offset + 2 );
	}
	else {
		my $count = $first & 0x7F;
		return ( undef, 'an indefinite length holds no whole element' )
		    unless $count;
		return ( undef,
			"a length of $count bytes is above the bound of "
			    . MAX_LENGTH_BYTES )
		    if $count > MAX_LENGTH_BYTES;
		return ( undef, 'the length bytes are truncated' )
		    unless $offset + 2 + $count <= $total;

		$length = 0;
		for my $index ( 0 .. $count - 1 ) {
			$length = ( $length << 8 ) +
			    ord( substr $der, $offset + 2 + $index, 1 );
		}
		$start = $offset + 2 + $count;
	}

	return ( undef, 'the element content is truncated' )
	    unless $start + $length <= $total;

	return ( {
			tag     => $tag,
			content => substr( $der, $start, $length ),
			next    => $start + $length,
		},
		undef
	);
}

# _expect($der, $offset, $tag, $what):
#	One DER element of the tag at the offset, or undef with the
#	reason as the second value. $what names the field, so the
#	reason of a walk names the field that failed.
sub _expect ( $der, $offset, $tag, $what )
{
	my ( $element, $reason ) = _element( $der, $offset );
	return ( undef, "$what: $reason" ) unless defined $element;

	return ( undef, sprintf '%s: tag 0x%02X, and not 0x%02X',
		$what, $element->{tag}, $tag )
	    unless $element->{tag} == $tag;

	return ( $element, undef );
}

# _name($bytes, $what):
#	A distinguished name as a hash reference of attribute type to
#	value, or undef with the reason as the second value.
#
#	A name holds a sequence of sets, and each set holds one
#	attribute or more. Two attributes of one type are a failure: a
#	hash holds one value for each type, and a caller that pins a
#	team identifier must never read one of two values.
sub _name ( $bytes, $what )
{
	my %name;
	my $offset = 0;

	while ( $offset < length $bytes ) {
		my ( $set, $set_reason ) = _expect( $bytes, $offset, TAG_SET,
			"$what: a relative distinguished name" );
		return ( undef, $set_reason ) unless defined $set;
		$offset = $set->{next};

		my $inner = 0;
		while ( $inner < length $set->{content} ) {
			my ( $pair, $pair_reason ) =
			    _expect( $set->{content}, $inner, TAG_SEQUENCE,
				"$what: an attribute" );
			return ( undef, $pair_reason ) unless defined $pair;
			$inner = $pair->{next};

			my ( $type, $value, $reason ) =
			    _attribute( $pair->{content}, $what );
			return ( undef, $reason ) unless defined $type;

			return ( undef, "$what: two attributes of type $type" )
			    if exists $name{$type};

			$name{$type} = $value;
		}
	}

	return ( \%name, undef );
}

# _attribute($bytes, $what):
#	The type and the value of one attribute, or undef with the
#	reason as the third value.
#
#	The value arrives as bytes. A UTF8String holds UTF-8, so a
#	caller that needs characters decodes them.
sub _attribute ( $bytes, $what )
{
	my ( $type, $type_reason ) =
	    _expect( $bytes, 0, TAG_OID, "$what: an attribute type" );
	return ( undef, undef, $type_reason ) unless defined $type;

	my ( $value, $value_reason ) = _element( $bytes, $type->{next} );
	return ( undef, undef, "$what: an attribute value: $value_reason" )
	    unless defined $value;

	return ( undef, undef, "$what: bytes follow an attribute value" )
	    unless $value->{next} == length $bytes;

	return (
		undef,
		undef,
		sprintf '%s: an attribute value is tag 0x%02X, and this '
		    . 'reader takes %s',
		$what,
		$value->{tag},
		join ', ',
		sort values %STRING_TAG
	) unless $STRING_TAG{ $value->{tag} };

	my $oid = _oid( $type->{content} );
	return ( undef, undef,
		"$what: an attribute type is no object " . 'identifier' )
	    unless defined $oid;

	return ( $ATTRIBUTE_NAME{$oid} // $oid, $value->{content}, undef );
}

# _oid($bytes):
#	The dotted form of an object identifier, or undef.
#
#	The first byte holds the first two arcs, and each later arc
#	takes seven bits of each byte. The high bit of a byte carries
#	the arc into the next one, so a high bit in the last byte
#	names an arc that the bytes do not hold.
sub _oid ($bytes)
{
	return unless length $bytes;

	my $first = ord substr $bytes, 0, 1;
	my @arc   = ( int( $first / 40 ), $first % 40 );

	my ( $value, $partial ) = ( 0, 0 );
	for my $byte ( unpack 'C*', substr $bytes, 1 ) {
		$value   = ( $value << 7 ) + ( $byte & 0x7F );
		$partial = 1;
		next if $byte & 0x80;
		push @arc, $value;
		( $value, $partial ) = ( 0, 0 );
	}

	return if $partial;

	return join '.', @arc;
}

# _time($element, $what):
#	One time of the validity, as seconds since the epoch, or undef
#	with the reason as the second value.
#
#	RFC 5280 section 4.1.2.5 holds each time to one of two forms.
#	A UTCTime writes YYMMDDHHMMSSZ, and a year of 50 or above
#	names the last century. A GeneralizedTime writes
#	YYYYMMDDHHMMSSZ, and every certificate that expires in 2050 or
#	later takes it. Both forms are UTC, and both hold the seconds.
#
#	The method reads each field before it computes, so the 31st of
#	February is a failure and never a date in March.
sub _time ( $element, $what )
{
	my $text = $element->{content};
	my ( $year, $rest );

	if ( $element->{tag} == TAG_UTC_TIME ) {
		return ( undef, "$what: a UTCTime holds YYMMDDHHMMSSZ" )
		    unless $text =~ /\A([0-9]{2})([0-9]{10})Z\z/;
		( $year, $rest ) = ( $1, $2 );
		$year += $year >= 50 ? 1900 : 2000;
	}
	elsif ( $element->{tag} == TAG_GENERALIZED_TIME ) {
		return ( undef,
			"$what: a GeneralizedTime holds YYYYMMDDHHMMSSZ" )
		    unless $text =~ /\A([0-9]{4})([0-9]{10})Z\z/;
		( $year, $rest ) = ( $1, $2 );
	}
	else {
		return ( undef, sprintf '%s: tag 0x%02X names no time',
			$what, $element->{tag} );
	}

	my ( $month, $day, $hour, $minute, $second ) =
	    map { 0 + $_ } unpack 'A2A2A2A2A2', $rest;

	return ( undef, "$what: month $month is no month" )
	    if $month < 1 || $month > 12;
	return ( undef, "$what: day $day is no day of month $month" )
	    if $day < 1 || $day > _month_days( $year, $month );
	return ( undef, "$what: $hour:$minute:$second is no time of day" )
	    if $hour > 23 || $minute > 59 || $second > 59;

	return ( _epoch( $year, $month, $day, $hour, $minute, $second ),
		undef );
}

# _month_days($year, $month):
#	The days of the month. A year that 4 divides is a leap year,
#	and a year that 100 divides is not, and a year that 400
#	divides is one again.
sub _month_days ( $year, $month )
{
	return $MONTH_DAYS[ $month - 1 ] unless $month == 2;

	my $leap = $year % 4 == 0 && ( $year % 100 != 0 || $year % 400 == 0 );

	return $leap ? 29 : 28;
}

# _epoch($year, $month, $day, $hour, $minute, $second):
#	The seconds since the epoch of a UTC date.
#
#	The sub counts the days from the civil date itself, over the
#	400-year cycle of the calendar. Time::Local would croak on a
#	date above the range of the integers of the build, and a
#	certificate comes from outside, so a die is no answer here.
sub _epoch ( $year, $month, $day, $hour, $minute, $second )
{
	# The year starts in March, so the leap day falls at the end
	# of it and every other month keeps its place.
	my $shifted = $year - ( $month <= 2 ? 1 : 0 );
	my $era     = int( $shifted / 400 );
	my $of_era  = $shifted - $era * 400;
	my $of_year =
	    int( ( 153 * ( $month + ( $month > 2 ? -3 : 9 ) ) + 2 ) / 5 ) +
	    $day - 1;
	my $day_of_era =
	    $of_era * 365 +
	    int( $of_era / 4 ) -
	    int( $of_era / 100 ) +
	    $of_year;

	# 719468 days separate the start of the era from the epoch.
	my $days = $era * 146_097 + $day_of_era - 719_468;

	return ( ( $days * 24 + $hour ) * 60 + $minute ) * 60 + $second;
}

# --- the process boundary -------------------------------------------------

# _find_command($name):
#	Resolve an executable path, or return undef. With a name that
#	holds a solidus the sub tests that path only. With a plain name
#	it walks $ENV{PATH} for that name. With no name it walks
#	$ENV{PATH} for openssl.
sub _find_command ( $name = undef )
{
	my @names = defined $name ? ($name) : ('openssl');

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
#	The openssl(1) command of one call, or undef with the reason
#	in error. new resolved the command once, so the method reads
#	that answer. It sets command_absent for the call, because a
#	command that never ran is an install problem.
sub _command ($self)
{
	return $self->{command} if defined $self->{command};

	$self->{command_absent} = 1;

	return $self->_set_error( _command_error( $self->{command_name} ) );
}

# _command_error($name):
#	The reason that no openssl(1) command resolved. new and each
#	command method write one shape, so a caller reads one string.
sub _command_error ( $name = undef )
{
	my $named = $name // 'openssl';

	return "no executable openssl command: $named";
}

# $self->_run($args, $what, $stdin):
#	Run one openssl(1) command. The method returns the result of
#	the run, or undef with the reason in error. The reason starts
#	with $what, which names the act that failed and the file of
#	it.
#
#	The command is a list, so no argument needs quoting and no
#	argument can become a shell operator.
#
#	A run that never reached the child means that openssl(1) never
#	ran, so command_absent reports 1 for that call.
sub _run ( $self, $args, $what, $stdin = undef )
{
	my $result = Fugu::Process->run(
		cmd     => [ $self->{command}, @$args ],
		timeout => OPENSSL_TIMEOUT,
		env     => _env(),
		( defined $stdin ? ( stdin => $stdin ) : () ),
	);

	return $result if $result->{success};

	if ( defined $result->{error} ) {
		$self->{command_absent} = 1;
		return $self->_set_error("$what: $result->{error}");
	}

	return $self->_set_error( "$what: " . _reason($result) );
}

# _env():
#	The environment of one openssl(1) run. The child takes this
#	set and nothing else, so no variable of the caller reaches the
#	command. OPENSSL_CONF of the caller names a configuration file,
#	and a CMS signature needs none. LC_ALL holds the diagnostics in
#	English, because _reason reads them.
sub _env ()
{
	return {
		PATH   => $ENV{PATH} // '',
		LC_ALL => 'C',
	};
}

# _reason($result):
#	The reason of an openssl(1) run that reached the child and
#	failed: the timeout, the reason of the first error record, the
#	first line of the diagnostic, or the exit code.
#
#	openssl(1) writes one error record in each line of a stack,
#	and a colon separates the fields: the process, the word error,
#	the code, the library, the function, the reason, the file and
#	the line. The first record names the fault, and each later one
#	names what the fault broke. A wrong certificate therefore
#	gives "signer certificate not found", and a changed file gives
#	"verification failure".
sub _reason ($result)
{
	return 'timeout after ' . OPENSSL_TIMEOUT . ' seconds'
	    if $result->{timed_out};

	my $first = '';
	for my $line ( split /\n/, $result->{stderr} // '' ) {
		next unless length $line;

		my @field = split /:/, $line, -1;
		return $field[5]
		    if @field >= 7
		    && $field[1] eq 'error'
		    && length $field[5];

		$first = $line unless length $first;
	}

	return length $first ? $first : "exit code $result->{exit_code}";
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

# _wide($text):
#	True when the string holds a code point above 255. Such a
#	string is character data and not bytes. Digest::SHA dies on it
#	with "Wide character in subroutine entry", and a byte read
#	takes the low byte of each character. The contract of this
#	module is a clean failure, so every method that takes bytes
#	tests this. A caller that holds text must encode it.
sub _wide ($text)
{
	return $text =~ /[^\x00-\xFF]/ ? 1 : 0;
}

# _fail($reason):
#	The failure return of every class method: undef in scalar
#	context, and undef with the reason in list context. One helper
#	keeps the two contexts in step.
sub _fail ($reason)
{
	return wantarray ? ( undef, $reason ) : undef;
}

1;
