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

package Fugu::Signify;

use Digest::SHA ();
use Fugu::Ed25519;
use Fugu::File;
use Fugu::Process;
use MIME::Base64 qw(decode_base64);

# Fugu::Signify - verify a signify(1) signature and a SHA256 manifest,
# and read and write the manifest form.
#
# The module verifies with two engines. The perl engine parses the
# signify(1) file formats and checks the signature with
# Fugu::Ed25519, so a host verifies a release with no command
# installed. It is the default. The signify engine runs signify(1)
# through Fugu::Process->run, with an argument list and never a
# shell. A caller that names a command asks for the command, so that
# call takes the signify engine.
#
# The module holds a small key set, so a caller can accept the
# current key and the next key. It also verifies each file that a
# signed SHA256 manifest names, against the digest of that manifest,
# with core Digest::SHA.
#
# A manifest holds one key in each line, between the parentheses. The
# key is opaque to this module: a release manifest writes a file name,
# and another producer writes a file path or a download URL. The
# caller maps each key to a local path, and the module reads no key as
# a path of its own.
#
# The module holds no private key, and it must not sign. A signature
# is a human act. Every recoverable failure returns undef, and error
# holds the reason. The module never logs: the caller decides what to
# report.

# The size bound of a manifest, 1 MiB. An OpenBSD SHA256 file holds
# tens of lines. A caller that names a disk image by mistake gets a
# clean failure, not a read of 500 MB.
use constant MAX_MANIFEST_SIZE => 1_048_576;

# The time bound of one signify(1) call, in seconds. A command that a
# caller named can be the wrong program. signify(1) itself needs
# milliseconds.
use constant SIGNIFY_TIMEOUT => 30;

# The size bound of a signify(1) public key file and signature file,
# 4 KiB. Each file holds two short lines. A caller that names a disk
# image by mistake gets a clean failure, not a read of 500 MB.
use constant MAX_SIGNIFY_FILE_SIZE => 4096;

# The first line of a signify(1) file. The line carries no trust: no
# signature covers it, and any producer writes any text after it.
use constant COMMENT_HEADER => 'untrusted comment: ';

# The two letters that name the algorithm at the front of each body.
use constant ALGORITHM => 'Ed';

# The length of the key number, in bytes. The number binds a
# signature to a key.
use constant KEYNUM_SIZE => 8;

# The byte length of the body of a public key file: the two letters,
# the key number, and the 32-byte public key.
use constant PUBLIC_KEY_SIZE => 42;

# The byte length of the body of a signature file: the two letters,
# the key number, and the 64-byte signature.
use constant SIGNATURE_SIZE => 74;

# Fugu::Signify->new(%args):
#	Build a verifier. Under the signify engine the method resolves
#	the command once, and it runs no process.
#
#	%args:
#		keys    => \@paths  # Required: public key files, in trust order
#		engine  => $engine  # Optional: perl or signify
#		command => $command # Optional: a name or an absolute path
#
#	The order of keys is the trust order: the current key first,
#	the next key second. The method dies when keys is absent, not
#	an array reference, or empty. Each one is a programming error,
#	and so is an engine name that the module does not hold.
#
#	The default engine is perl. A caller that names a command asks
#	for the command, so that call defaults to the signify engine.
#
#	The method must not die for an absent command. It sets error
#	instead, and is_available then returns 0.
sub new ( $class, %args )
{
	my $keys = $args{keys};
	die "keys must be a non-empty array reference\n"
	    unless ref $keys eq 'ARRAY' && @$keys;

	my $engine = $args{engine}
	    // ( defined $args{command} ? 'signify' : 'perl' );
	die "engine must be perl or signify\n"
	    unless $engine eq 'perl' || $engine eq 'signify';

	my $self = bless {
		keys           => [@$keys],
		engine         => $engine,
		ed25519        => Fugu::Ed25519->new,
		command        => undef,
		command_error  => undef,
		command_absent => 0,
		error          => undef,
	}, $class;

	# The perl engine needs no command, so the object never walks
	# the search list and never holds an install failure.
	return $self if $engine eq 'perl';

	my $command = _find_command( $args{command} );
	if ( defined $command ) {
		$self->{command} = $command;
	}
	else {
		my $named = $args{command} // 'signify-openbsd, signify';
		$self->{command_error} =
		    "no executable signify command: $named";
		$self->{error}          = $self->{command_error};
		$self->{command_absent} = 1;
	}

	return $self;
}

# $self->is_available:
#	Report if the object can verify. The perl engine always can,
#	so it returns 1. The signify engine returns 1 when it resolved
#	an executable command, and 0 otherwise. The method runs no
#	process, and it never dies.
sub is_available ($self)
{
	return 1 if $self->{engine} eq 'perl';

	return defined $self->{command} ? 1 : 0;
}

# $self->command:
#	The resolved command path, or undef. The perl engine runs no
#	command, so it returns undef. An operator who installed the
#	wrong signify needs this answer in a diagnostic.
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
#	Report if the most recent failure means that signify(1) never
#	ran: the search list did not resolve the command, or the
#	command failed to execve(2). An absent command is an install
#	problem, and a failed signature is an integrity problem. The
#	caller must tell them apart.
sub command_absent ($self)
{
	return $self->{command_absent} ? 1 : 0;
}

# $self->verify($file, $sigfile):
#	Verify one file against the key set, in order. $sigfile
#	defaults to "$file.sig", the default of signify(1) itself.
#
#	The method returns the public key file that verified the
#	signature. It returns undef on every failure, and error holds
#	the reason. For a signature that no key verified, the reason
#	names the file, then each key with its own reason. Both
#	engines write that shape, so a caller tells a wrong key from
#	an absent key file under either one.
sub verify ( $self, $file, $sigfile = undef )
{
	$self->{error}          = undef;
	$self->{command_absent} = 0;

	if ( $self->{engine} eq 'signify' && !defined $self->{command} ) {
		$self->{error}          = $self->{command_error};
		$self->{command_absent} = 1;
		return;
	}

	$sigfile //= "$file.sig";

	# One check covers every key, and it names the missing path.
	for my $path ( $file, $sigfile ) {
		next if -f $path;
		$self->{error} = "not a plain file: $path";
		return;
	}

	return $self->_verify_perl( $file, $sigfile )
	    if $self->{engine} eq 'perl';

	return $self->_verify_signify( $file, $sigfile );
}

# $self->parse_public_key($bytes):
#	Parse a signify(1) public key file. The method returns a hash
#	reference with comment, keynum and key, or undef with the
#	reason in error.
#
#	The comment carries no trust. The key number binds the key to
#	a signature, and the key is the 32 bytes that Fugu::Ed25519
#	takes.
sub parse_public_key ( $self, $bytes )
{
	$self->{error} = undef;

	my ( $parsed, $reason ) = _parse_file( $bytes, PUBLIC_KEY_SIZE );
	unless ( defined $parsed ) {
		$self->{error} = $reason;
		return;
	}

	return {
		comment => $parsed->{comment},
		keynum  => $parsed->{keynum},
		key     => $parsed->{payload},
	};
}

# $self->parse_signature($bytes):
#	Parse a signify(1) signature file. The method returns a hash
#	reference with comment, keynum and signature, or undef with
#	the reason in error.
#
#	The signature is the 64 bytes that Fugu::Ed25519 takes, and it
#	covers the bytes of the signed file.
sub parse_signature ( $self, $bytes )
{
	$self->{error} = undef;

	my ( $parsed, $reason ) = _parse_file( $bytes, SIGNATURE_SIZE );
	unless ( defined $parsed ) {
		$self->{error} = $reason;
		return;
	}

	return {
		comment   => $parsed->{comment},
		keynum    => $parsed->{keynum},
		signature => $parsed->{payload},
	};
}

# $self->verify_manifest(%args):
#	Verify a signed SHA256 manifest, and then verify the digest of
#	each file that the caller names.
#
#	%args:
#		manifest  => $path  # Required: the signed SHA256 file
#		signature => $path  # Optional: default "$manifest.sig"
#		files     => \%map  # Required: manifest key => local path
#
#	A key of files is a key of the manifest, and the module
#	compares it as text. It can be a file name, a file path, or a
#	download URL, whichever the producer of the manifest wrote.
#	The value is the local path that the module digests, so the
#	caller decides where the bytes sit.
#
#	The module must never choose which file to check, so an empty
#	files is a programming error, and the method dies. The method
#	returns the public key file that verified the manifest, or
#	undef on every failure. No file is digested before the
#	manifest verifies.
sub verify_manifest ( $self, %args )
{
	my $manifest = $args{manifest};
	die "manifest is a necessary argument\n"
	    unless defined $manifest;

	my $files = $args{files};
	die "files must be a non-empty hash reference\n"
	    unless ref $files eq 'HASH' && %$files;

	my $signature = $args{signature} // "$manifest.sig";

	my $keyfile = $self->verify( $manifest, $signature );
	return unless defined $keyfile;

	# The bound reads the size on disk, before the content.
	my $size = -s $manifest;
	if ( !defined $size || $size > MAX_MANIFEST_SIZE ) {
		$self->{error} = sprintf '%s: manifest is larger than %d bytes',
		    $manifest, MAX_MANIFEST_SIZE;
		return;
	}

	my $bytes = Fugu::File->read($manifest);
	unless ( defined $bytes ) {
		$self->{error} = "cannot read $manifest";
		return;
	}

	my $digests = $self->_parse_manifest($bytes);
	return unless defined $digests;

	for my $key ( sort keys %$files ) {
		my $expected = $digests->{$key};
		unless ( defined $expected ) {
			$self->{error} = "$manifest does not hold $key";
			return;
		}

		my $path     = $files->{$key};
		my $computed = _digest($path);
		unless ( defined $computed ) {
			$self->{error} = "cannot digest $path: $!";
			return;
		}

		if ( $computed ne $expected ) {
			$self->{error} = "$key: digest mismatch:"
			    . " expected $expected, computed $computed";
			return;
		}
	}

	return $keyfile;
}

# $self->parse_manifest($bytes):
#	The public form of the parser that verify_manifest uses. The
#	method returns a hash reference of manifest key to lowercase
#	hex digest, or undef with the reason in error.
#
#	Two callers read a manifest without a signature at that
#	moment. A rotation writes a manifest, and it must read the
#	file that it wrote. A site check compares a manifest against
#	the files beside it, and a site build cannot sign. A private
#	parser would make each one write the line form again.
#
#	The method verifies nothing. A caller that needs the signature
#	calls verify_manifest, which verifies the signature before it
#	digests one file.
sub parse_manifest ( $self, $bytes )
{
	$self->{error} = undef;

	unless ( defined $bytes ) {
		$self->{error} = 'the manifest bytes are undef';
		return;
	}

	if ( $bytes =~ /[^\x00-\xFF]/ ) {
		$self->{error} = 'the manifest holds a character above 255, '
		    . 'and a manifest holds bytes';
		return;
	}

	return $self->_parse_manifest($bytes);
}

# $self->write_manifest($digests):
#	The text of a SHA256 manifest, or undef with the reason in
#	error.
#
#	Each line holds 'SHA256 (key) = digest'. The keys sort in
#	ascending order, so two runs of a rotation write one byte
#	sequence, and a diff of two manifests then shows the change
#	only.
#
#	The key is a file name, a file path, or a download URL,
#	whichever the producer writes. The method therefore rejects
#	only a key that another reader cannot carry. _parse_manifest
#	takes the text up to the last parenthesis, so it reads such a
#	key back without a change. A stricter reader does not: a
#	parenthesis ends the key in a reader that stops at the first
#	one, and whitespace breaks a reader that splits a line on
#	space. A manifest travels to sha256(1) and to scripts/deps, so
#	the writer holds a key to the strict form.
sub write_manifest ( $self, $digests )
{
	$self->{error} = undef;

	unless ( ref $digests eq 'HASH' ) {
		die "digests must be a hash reference\n";
	}

	unless (%$digests) {
		$self->{error} = 'the digest set is empty';
		return;
	}

	# A manifest is bytes. A key that holds a code point above 255
	# is character data, and print then writes its UTF-8 form: the
	# bytes on disk differ from the key that the caller passed, so
	# the manifest names a file that no reader finds. Perl also
	# warns "Wide character in print". Fugu::OpenPGP fails such a
	# string, and this method must agree.
	for my $key ( sort keys %$digests ) {
		next unless $key =~ /[^\x00-\xFF]/;
		$self->{error} = 'a manifest key holds a character above '
		    . '255, and a manifest holds bytes';
		return;
	}

	my $text = '';
	for my $key ( sort keys %$digests ) {
		unless ( length $key ) {
			$self->{error} = 'a manifest key is empty';
			return;
		}

		if ( $key =~ /[()]/ ) {
			$self->{error} =
			    "a manifest key holds a parenthesis: $key";
			return;
		}

		# The class names the ASCII whitespace only. \s reads a
		# byte above 127 as Latin-1 under the feature set of
		# this file, so it matches U+0085 and U+00A0 and would
		# reject a UTF-8 file name that holds a letter such as
		# a-ogonek. A rotation would then stall on a release
		# asset whose name is valid.
		if ( $key =~ /[ \t\n\r\f\x0B]/ ) {
			$self->{error} =
			    "a manifest key holds whitespace: $key";
			return;
		}

		my $digest = $digests->{$key};
		unless ( defined $digest && $digest =~ /\A[0-9A-Fa-f]{64}\z/ ) {
			$self->{error} = "the digest of $key is not 64 "
			    . 'hexadecimal characters';
			return;
		}

		$text .= "SHA256 ($key) = " . lc($digest) . "\n";
	}

	return $text;
}

# $self->_verify_perl($file, $sigfile):
#	Verify with Fugu::Ed25519, and never with a command. The
#	method parses the signature file once, and then walks the key
#	set in trust order. It returns the key file that verified the
#	signature, or undef with the reason in error.
sub _verify_perl ( $self, $file, $sigfile )
{
	my $bytes = _read_bounded($sigfile);
	unless ( defined $bytes ) {
		$self->{error} = sprintf
		    '%s: cannot read a signify file under %d bytes',
		    $sigfile, MAX_SIGNIFY_FILE_SIZE;
		return;
	}

	my $signature = $self->parse_signature($bytes);
	unless ( defined $signature ) {

		# Both engines must write one error shape. The
		# signify(1) engine reads the signature file once for
		# each key, so a malformed file gives one reason for
		# each key. This parse runs once, and its reason
		# stands against every key of the set.
		my $reason = $self->{error};
		$self->{error} = _no_key_verified( $file,
			map { "$_: $reason" } @{ $self->{keys} } );
		return;
	}

	my @reasons;
	for my $keyfile ( @{ $self->{keys} } ) {
		my $reason = $self->_verify_key( $keyfile, $signature, $file );

		# The key parser reports through error, so the reason
		# of one key must not survive as the reason of the
		# whole call.
		$self->{error} = undef;
		return $keyfile unless defined $reason;
		push @reasons, "$keyfile: $reason";
	}

	$self->{error} = _no_key_verified( $file, @reasons );

	return;
}

# $self->_verify_key($keyfile, $signature, $file):
#	Check one file against one public key file. The method
#	returns undef when the signature verifies, and the reason
#	otherwise.
#
#	A key number that differs from the signature gives "checked
#	against wrong key", which is the diagnostic of signify(1)
#	itself. The loop of the caller then continues to the next key.
sub _verify_key ( $self, $keyfile, $signature, $file )
{
	my $bytes = _read_bounded($keyfile);
	return sprintf 'cannot read a signify file under %d bytes',
	    MAX_SIGNIFY_FILE_SIZE
	    unless defined $bytes;

	my $key = $self->parse_public_key($bytes);
	return $self->{error} unless defined $key;

	return 'checked against wrong key'
	    unless $key->{keynum} eq $signature->{keynum};

	my $verified = $self->{ed25519}->verify(
		key       => $key->{key},
		signature => $signature->{signature},
		file      => $file,
	);

	# undef means that the verifier refused the input, and the
	# reason belongs to this key.
	return $self->{ed25519}->error unless defined $verified;

	return 'signature verification failed' unless $verified;

	return;
}

# $self->_verify_signify($file, $sigfile):
#	Verify by running signify(1) over each key of the set. The
#	method returns the key file that verified the signature, or
#	undef with the reason in error.
sub _verify_signify ( $self, $file, $sigfile )
{
	my @reasons;
	for my $keyfile ( @{ $self->{keys} } ) {
		my $result = $self->_run_signify( $keyfile, $sigfile, $file );
		return $keyfile if $result->{success};

		# A run that never reached the child means that
		# signify(1) never ran. That is an install problem, so
		# the loop stops: every later key would fail the same
		# way.
		if ( defined $result->{error} ) {
			$self->{error}          = $result->{error};
			$self->{command_absent} = 1;
			return;
		}

		my $reason;
		if ( $result->{timed_out} ) {
			$reason =
			    'timeout after ' . SIGNIFY_TIMEOUT . ' seconds';
		}
		else {
			# The first line of the diagnostic, without the
			# program name in front.
			($reason) = split /\n/, $result->{stderr} // '';
			$reason //= '';
			$reason =~ s/^\S*signify\S*:\s*//;
			$reason = "exit code $result->{exit_code}"
			    unless length $reason;
		}
		push @reasons, "$keyfile: $reason";
	}

	$self->{error} = _no_key_verified( $file, @reasons );

	return;
}

# _no_key_verified($file, @reasons):
#	The error of a verification that no key passed: the file,
#	then one reason for each key of the set. Both engines write
#	this shape, so a caller reads one shape under either engine.
sub _no_key_verified ( $file, @reasons )
{
	return "$file: no key verified the signature:\n    "
	    . join( ";\n    ", @reasons );
}

# _read_bounded($path):
#	The bytes of a signify(1) file, or undef. The bound reads the
#	size on disk, before the content, so a file that a caller
#	named by mistake never enters memory.
sub _read_bounded ($path)
{
	my $size = -s $path;
	return if !defined $size || $size > MAX_SIGNIFY_FILE_SIZE;

	return Fugu::File->read($path);
}

# _parse_file($bytes, $size):
#	Parse the two lines of a signify(1) file. A public key file
#	and a signature file share the shape: the comment line, then
#	the base64 body. The body holds the two letters Ed, the key
#	number, and the key or the signature.
#
#	The sub returns the hash reference and undef, or undef and
#	the reason. The comment carries no trust, so the sub reads it
#	and tests nothing after the header.
#
#	decode_base64 skips a character that no base64 alphabet
#	holds, so a body of the right character count with one bad
#	character decodes short. The two length tests together
#	therefore hold the body to the exact form.
sub _parse_file ( $bytes, $size )
{
	return ( undef, 'the file is undef' ) unless defined $bytes;

	return ( undef,
		      'the file holds a character above 255, and a '
		    . 'signify file holds bytes' )
	    if $bytes =~ /[^\x00-\xFF]/;

	# A list assignment would give split an implicit limit, and a
	# trailing empty field would then survive as a body. The array
	# takes the whole split, so a file of one line fails, and so
	# does a file of three.
	my @lines = split /\n/, $bytes;
	return ( undef, 'a signify file holds two lines' )
	    unless @lines == 2;

	my ( $comment, $body ) = @lines;

	return ( undef, 'the first line is no untrusted comment' )
	    unless index( $comment, COMMENT_HEADER ) == 0;

	my $characters = 4 * int( ( $size + 2 ) / 3 );
	return ( undef, "the body is not $characters base64 characters" )
	    unless length($body) == $characters;

	my $raw = decode_base64($body);
	return ( undef, "the body is not $size bytes" )
	    unless length($raw) == $size;

	return ( undef, 'the body names no Ed25519 key or signature' )
	    unless index( $raw, ALGORITHM ) == 0;

	return ( {
			comment => substr( $comment, length COMMENT_HEADER ),
			keynum  =>
			    substr( $raw, length(ALGORITHM), KEYNUM_SIZE ),
			payload =>
			    substr( $raw, length(ALGORITHM) + KEYNUM_SIZE ),
		},
		undef
	);
}

# _find_command($name):
#	Resolve an executable path, or return undef. With a name that
#	holds a solidus the sub tests that path only. With a plain
#	name it walks $ENV{PATH} for that name. With no name it walks
#	$ENV{PATH} over the search list: signify-openbsd, then
#	signify. On Debian the plain name signify belongs to an
#	unrelated package, and the OpenBSD-specific name exists only
#	where the real program is installed.
sub _find_command ( $name = undef )
{
	my @names = defined $name ? ($name) : ( 'signify-openbsd', 'signify' );

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

# $self->_run_signify($keyfile, $sigfile, $file):
#	Run one signify(1) verification through Fugu::Process->run.
#	The command is a list, so no argument needs quoting and no
#	argument can become a shell operator. -q suppresses the
#	success line: the caller reads the exit code and the standard
#	error only.
sub _run_signify ( $self, $keyfile, $sigfile, $file )
{
	my @cmd = (
		$self->{command}, '-V', '-q',     '-p',
		$keyfile,         '-x', $sigfile, '-m',
		$file,
	);

	return Fugu::Process->run(
		cmd     => \@cmd,
		timeout => SIGNIFY_TIMEOUT,
	);
}

# $self->_parse_manifest($bytes):
#	Parse the OpenBSD sha256(1) line form:
#
#		SHA256 (miniroot78.img) = 4f2b...
#		SHA256 (dist/miniroot78.img) = 4f2b...
#		SHA256 (https://example.org/dl/miniroot78.img) = 4f2b...
#
#	The key sits between the parentheses, and this method holds it
#	as text. A release manifest writes a file name, and another
#	producer writes a file path or a download URL. The pattern
#	takes the whole text up to the last parenthesis, so a key with
#	a solidus, a colon or a dot reads like any other.
#
#	The method returns a hash reference of key to lowercase hex
#	digest, or undef with the reason in error. Like Fugu::Config,
#	the parser never skips a line: an empty manifest, a line it
#	cannot parse, a digest that is not 64 hexadecimal characters,
#	and a duplicate key are each a failure.
sub _parse_manifest ( $self, $bytes )
{
	my %digest;
	for my $line ( split /\n/, $bytes ) {
		my ( $key, $hex ) =
		    $line =~ /^SHA256 \((.+)\) = ([0-9A-Fa-f]+)$/;
		unless ( defined $key ) {
			$self->{error} = "cannot parse manifest line: $line";
			return;
		}
		if ( length($hex) != 64 ) {
			$self->{error} =
			    "digest of $key is not 64 hexadecimal characters";
			return;
		}
		if ( exists $digest{$key} ) {
			$self->{error} = "duplicate manifest key: $key";
			return;
		}
		$digest{$key} = lc $hex;
	}

	unless ( keys %digest ) {
		$self->{error} = 'the manifest is empty';
		return;
	}

	return \%digest;
}

# _digest($path):
#	The lowercase hex SHA256 digest of the file, or undef when the
#	file does not open. addfile reads in blocks, so a file set of
#	500 MB never enters memory whole.
sub _digest ($path)
{
	open my $fh, '<', $path or return;
	binmode $fh;

	my $sha = Digest::SHA->new(256);
	$sha->addfile($fh);
	close $fh;

	return lc $sha->hexdigest;
}

1;
