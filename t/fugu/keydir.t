#!/usr/bin/env perl
# ex:ts=8 sw=4:
# Guards for Fugu::KeyDir
#
# The module holds the names, the order and the generated text of a
# published key directory. It holds no policy, so each test supplies
# the organization word, the purposes and the dates.
#
# The order tests read the byte sequence, not a set. A site build
# writes the index page and the KEYS file on every build, so an
# unstable order would make a diff on each run.

use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use_ok('Fugu::KeyDir');

my $kd = Fugu::KeyDir->new( org => 'fugubsd' );

# An armored body for the KEYS tests. The bytes never reach a parser
# here: keys_file copies the field as text.
use constant ARMOR => "-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n"
    . "mDMEfake\n=abcd\n-----END PGP PUBLIC KEY BLOCK-----";

subtest 'new holds the organization word' => sub {
	is( $kd->org, 'fugubsd', 'org reports the word' );

	ok( !eval { Fugu::KeyDir->new; 1 }, 'new dies for an absent org' );
	like( $@, qr/necessary/, 'and the reason says so' );

	ok( !eval { Fugu::KeyDir->new( org => 'FuguBSD' ); 1 },
		'new dies for an upper-case org' );
	ok( !eval { Fugu::KeyDir->new( org => 'fugu-bsd' ); 1 },
		'new dies for an org with a hyphen' );
	ok( !eval { Fugu::KeyDir->new( org => '1fugu' ); 1 },
		'new dies for an org that starts on a digit' );
};

subtest 'the module runs no command and cannot sign' => sub {
	for my $name (qw(sign generate rotate)) {
		ok( !Fugu::KeyDir->can($name), "no $name method exists" );
	}
};

subtest 'parse_name reads a valid name of each type' => sub {
	my $signify = $kd->parse_name('fugubsd-1-release.pub');
	is_deeply(
		$signify,
		{
			stem    => 'fugubsd-1-release',
			org     => 'fugubsd',
			serial  => 1,
			purpose => 'release',
			type    => 'signify',
		},
		'a .pub name gives the signify type'
	);

	my $openpgp = $kd->parse_name('fugubsd-12-mail.asc');
	is( $openpgp->{type},   'openpgp', 'a .asc name gives the openpgp type' );
	is( $openpgp->{serial}, 12,        'a two-digit serial reads as 12' );

	# The serial must be a number, so a sort of 2 and 10 puts 10
	# second. A text sort would put 10 first.
	my @serials =
	    map { $kd->parse_name($_)->{serial} }
	    qw(fugubsd-2-release.pub fugubsd-10-release.pub);
	is_deeply( [ sort { $a <=> $b } @serials ],
		[ 2, 10 ], 'a serial sorts as a number' );

	is( $kd->parse_name('fugubsd-1-code-signing.pub')->{purpose},
		'code-signing', 'a purpose can hold a hyphen' );
};

subtest 'parse_name rejects a bad name' => sub {
	my %bad = (
		'fugustx-1-release.pub'  => qr/names the organization fugustx/,
		'fugubsd-01-release.pub' => qr/serial is padded/,
		'fugubsd-0-release.pub'  => qr/serial is zero/,
		'fugubsd-1-release.key'  => qr/unknown key extension/,
		'fugubsd-1-Release.pub'  => qr/does not match/,
		'fugubsd-1-release'      => qr/holds no extension/,
		'fugubsd-release.pub'    => qr/does not match/,
		'keys/fugubsd-1-release.pub' => qr/holds a solidus/,
		''                           => qr/empty/,
	);

	for my $name ( sort keys %bad ) {
		is( $kd->parse_name($name), undef, "'$name' fails" );
		like( $kd->error, $bad{$name}, "and the reason names the fault" );
	}

	is( $kd->parse_name(undef), undef, 'undef fails' );
};

subtest 'name_for is the inverse of parse_name' => sub {
	is( $kd->name_for( serial => 1, purpose => 'release', type => 'signify' ),
		'fugubsd-1-release.pub', 'a signify name' );
	is( $kd->name_for( serial => 2, purpose => 'mail', type => 'openpgp' ),
		'fugubsd-2-mail.asc', 'an openpgp name' );

	# The round trip must return the parts that went in.
	for my $type (qw(signify openpgp)) {
		my $name = $kd->name_for(
			serial  => 7,
			purpose => 'release',
			type    => $type,
		);
		my $parts = $kd->parse_name($name);
		is( $parts->{serial},  7,         "$type round trip: serial" );
		is( $parts->{purpose}, 'release', "$type round trip: purpose" );
		is( $parts->{type},    $type,     "$type round trip: type" );
	}

	is( $kd->name_for( serial => 0, purpose => 'release', type => 'signify' ),
		undef, 'a zero serial fails' );
	is( $kd->name_for( serial => '01', purpose => 'x', type => 'signify' ),
		undef, 'a padded serial fails' );
	is( $kd->name_for( serial => 1, purpose => 'Release', type => 'signify' ),
		undef, 'an upper-case purpose fails' );
	is( $kd->name_for( serial => 1, purpose => 'release', type => 'gpg' ),
		undef, 'an unknown type fails' );
	like( $kd->error, qr/unknown key type/, 'and the reason says so' );
};

subtest 'next_serial adds one to the highest of the purpose' => sub {
	is( $kd->next_serial( [], 'release' ),
		1, 'an empty directory starts at 1' );

	is(
		$kd->next_serial(
			[qw(fugubsd-1-release.pub fugubsd-3-release.pub)],
			'release'
		),
		4,
		'the highest serial decides, not the count'
	);

	# A second purpose starts at 1, so a compromise of one purpose
	# leaves the others in force.
	my @names = qw(
	    fugubsd-1-release.pub
	    fugubsd-2-release.pub
	    fugubsd-5-mail.asc
	);
	is( $kd->next_serial( \@names, 'release' ), 3, 'release goes to 3' );
	is( $kd->next_serial( \@names, 'mail' ),    6, 'mail goes to 6' );
	is( $kd->next_serial( \@names, 'code' ),    1, 'a new purpose starts at 1' );

	is( $kd->next_serial( ['fugubsd-01-release.pub'], 'release' ),
		undef, 'a name that parse_name rejects fails' );
	like( $kd->error, qr/padded/, 'and the reason names the fault' );

	is( $kd->next_serial( [], '' ), undef, 'an empty purpose fails' );

	ok( !eval { $kd->next_serial( 'not a reference', 'release' ); 1 },
		'a non-reference dies' );
};

subtest 'order writes one byte sequence' => sub {
	my @keys = (
		{ name => 'fugubsd-1-release.pub', status => 'retired' },
		{ name => 'fugubsd-3-release.pub', status => 'current' },
		{ name => 'fugubsd-4-release.pub', status => 'next' },
		{ name => 'fugubsd-2-release.pub', status => 'retired' },
	);

	my $ordered = $kd->order( \@keys ) or diag( $kd->error );
	is_deeply(
		[ map { $_->{name} } @$ordered ],
		[
			'fugubsd-3-release.pub',
			'fugubsd-4-release.pub',
			'fugubsd-2-release.pub',
			'fugubsd-1-release.pub',
		],
		'current, then next, then retired by descending serial'
	);

	# The method adds the parts of the name, so a caller reads the
	# serial without a second parse.
	is( $ordered->[0]{serial},  3,         'the entry holds the serial' );
	is( $ordered->[0]{purpose}, 'release', 'and the purpose' );
	is( $ordered->[0]{type},    'signify', 'and the type' );
	is( $ordered->[0]{stem}, 'fugubsd-3-release', 'and the stem' );

	# A reversed input must give the same output. Without a total
	# order the two runs would differ.
	my $again = $kd->order( [ reverse @keys ] );
	is_deeply( [ map { $_->{name} } @$again ],
		[ map { $_->{name} } @$ordered ],
		'a reversed input gives the same order' );

	# Two purposes at one serial: the purpose breaks the tie.
	my $mixed = $kd->order(
		[
			{ name => 'fugubsd-1-release.pub', status => 'current' },
			{ name => 'fugubsd-1-mail.asc',    status => 'current' },
		]
	);
	is_deeply(
		[ map { $_->{name} } @$mixed ],
		[ 'fugubsd-1-mail.asc', 'fugubsd-1-release.pub' ],
		'the purpose breaks a tie at one serial'
	);

	# The method must not mutate its own input.
	is( scalar keys %{ $keys[0] }, 2, 'the input key keeps its two fields' );
};

subtest 'order holds each key to the vocabulary' => sub {
	is(
		$kd->order(
			[ { name => 'fugubsd-1-release.pub', status => 'live' } ]
		),
		undef,
		'a status outside the vocabulary fails'
	);
	like( $kd->error, qr/the vocabulary is current, next, retired/,
		'and the reason names the vocabulary' );

	is( $kd->order( [ { name => 'fugubsd-1-release.pub' } ] ),
		undef, 'an absent status fails' );

	is( $kd->order( [] ), undef, 'an empty set fails' );
	like( $kd->error, qr/empty/, 'and the reason says so' );

	is(
		$kd->order(
			[
				{
					name   => 'fugubsd-1-release.pub',
					status => 'current'
				},
				{
					name   => 'fugubsd-1-release.pub',
					status => 'retired'
				},
			]
		),
		undef,
		'one name twice fails'
	);
	like( $kd->error, qr/twice/, 'and the reason says so' );

	ok( !eval { $kd->order('not a reference'); 1 },
		'a non-reference dies' );
	ok( !eval { $kd->order( ['not a hash'] ); 1 },
		'a key that is not a hash reference dies' );
};

subtest 'check_statuses holds one current key for each purpose' => sub {
	my @good = (
		{ name => 'fugubsd-1-release.pub', status => 'retired' },
		{ name => 'fugubsd-2-release.pub', status => 'current' },
		{ name => 'fugubsd-3-release.pub', status => 'next' },
		{ name => 'fugubsd-1-mail.asc',    status => 'current' },
	);
	is( $kd->check_statuses( \@good ), 1, 'a valid set passes' );
	is( $kd->error, undef, 'and it reports no reason' );

	# Two current keys is the dangerous case: a reader cannot tell
	# which key signs a release today.
	my @two_current = (
		{ name => 'fugubsd-1-release.pub', status => 'current' },
		{ name => 'fugubsd-2-release.pub', status => 'current' },
	);
	is( $kd->check_statuses( \@two_current ),
		undef, 'two current keys of one purpose fail' );
	like( $kd->error, qr/release holds 2 current keys/,
		'and the reason names the purpose and the count' );

	my @two_next = (
		{ name => 'fugubsd-1-release.pub', status => 'current' },
		{ name => 'fugubsd-2-release.pub', status => 'next' },
		{ name => 'fugubsd-3-release.pub', status => 'next' },
	);
	is( $kd->check_statuses( \@two_next ),
		undef, 'two next keys of one purpose fail' );
	like( $kd->error, qr/release holds 2 next keys/,
		'and the reason says so' );

	my @no_current =
	    ( { name => 'fugubsd-1-release.pub', status => 'retired' } );
	is( $kd->check_statuses( \@no_current ),
		undef, 'a purpose with no current key fails' );
	like( $kd->error, qr/release holds 0 current keys/,
		'and the reason says so' );

	# A second purpose must not hide the fault of the first.
	my @one_bad = (
		{ name => 'fugubsd-1-release.pub', status => 'current' },
		{ name => 'fugubsd-1-mail.asc',    status => 'retired' },
	);
	is( $kd->check_statuses( \@one_bad ),
		undef, 'one bad purpose beside a good one fails' );
	like( $kd->error, qr/mail holds 0 current keys/,
		'and the reason names the bad purpose' );
};

subtest 'keys_file holds each OpenPGP key in order' => sub {
	my @keys = (
		{
			name        => 'fugubsd-1-mail.asc',
			status      => 'retired',
			armor       => ARMOR,
			fingerprint => 'AAAA',
		},
		{
			name        => 'fugubsd-2-mail.asc',
			status      => 'current',
			armor       => ARMOR,
			fingerprint => 'BBBB',
			since       => '2026-09-06',
		},
		{ name => 'fugubsd-1-release.pub', status => 'current' },
	);

	my $text = $kd->keys_file( \@keys ) or diag( $kd->error );

	# gpg --import reads this file, and it cannot read a signify
	# key, so the signify stem must not appear.
	unlike( $text, qr/fugubsd-1-release/,
		'the file holds no signify key' );

	like( $text, qr/fugubsd-2-mail/, 'the file holds the current key' );
	like( $text, qr/fugubsd-1-mail/, 'and the retired key' );

	# The current key leads, so a reader imports the key in force
	# first.
	ok( index( $text, 'fugubsd-2-mail' ) < index( $text, 'fugubsd-1-mail' ),
		'the current key comes before the retired key' );

	like( $text, qr/^fingerprint: BBBB$/m, 'the comment holds the fingerprint' );
	like( $text, qr/^since: 2026-09-06$/m, 'and the date' );
	like( $text, qr/^status: current$/m,   'and the status' );

	is( scalar( () = $text =~ /BEGIN PGP PUBLIC KEY BLOCK/g ),
		2, 'the file holds two armored bodies' );

	# A set with no OpenPGP key gives empty text, and not a
	# failure: a site can publish signify keys only.
	my $only_signify =
	    $kd->keys_file(
		[ { name => 'fugubsd-1-release.pub', status => 'current' } ] );
	is( $only_signify, '', 'a signify-only set gives empty text' );

	is(
		$kd->keys_file(
			[ { name => 'fugubsd-1-mail.asc', status => 'current' } ]
		),
		undef,
		'an OpenPGP key with no armor fails'
	);
	like( $kd->error, qr/holds no armor/, 'and the reason says so' );
};

subtest 'index_data holds one row for each key, in order' => sub {
	my @keys = (
		{ name => 'fugubsd-1-release.pub', status => 'retired' },
		{
			name        => 'fugubsd-2-release.pub',
			status      => 'current',
			since       => '2026-09-06',
			fingerprint => 'CCCC',
			email       => 'security@fugubsd.org',
		},
	);

	my $rows = $kd->index_data( \@keys ) or diag( $kd->error );
	is( scalar @$rows, 2, 'one row for each key' );

	is( $rows->[0]{name},        'fugubsd-2-release.pub', 'the current key leads' );
	is( $rows->[0]{serial},      2,                       'the row holds the serial' );
	is( $rows->[0]{purpose},     'release',               'and the purpose' );
	is( $rows->[0]{type},        'signify',               'and the type' );
	is( $rows->[0]{status},      'current',               'and the status' );
	is( $rows->[0]{fingerprint}, 'CCCC',                  'and the fingerprint' );
	is( $rows->[0]{since},       '2026-09-06',            'and the date' );
	is( $rows->[0]{email}, 'security@fugubsd.org', 'and the email' );

	# An absent optional field stays undef, so a template tests
	# one thing and never two.
	ok( exists $rows->[1]{fingerprint},
		'an absent fingerprint still holds the field' );
	is( $rows->[1]{fingerprint}, undef, 'and the value is undef' );
	is( $rows->[1]{until},       undef, 'the same for until' );

	# The method renders no HTML: the site owns the template.
	unlike( join( '', map { join '', grep { defined } values %$_ } @$rows ),
		qr/</, 'no row holds markup' );
};

subtest 'security_txt writes the fields of RFC 9116' => sub {
	my $text = $kd->security_txt(
		contact => 'mailto:security@fugubsd.org',
		expires => '2027-01-01T00:00:00Z',
		encryption =>
		    'https://www.fugubsd.org/keys/fugubsd-1-mail.asc',
	) or diag( $kd->error );

	like( $text, qr/^Contact: mailto:security\@fugubsd\.org$/m,
		'the text holds the contact' );
	like( $text, qr/^Expires: 2027-01-01T00:00:00Z$/m, 'and the expiry' );
	like(
		$text,
		qr{^Encryption: https://www\.fugubsd\.org/keys/fugubsd-1-mail\.asc$}m,
		'and the encryption field'
	);

	# The RFC states that the field order carries the preference
	# of the operator, so Contact leads.
	ok( index( $text, 'Contact:' ) < index( $text, 'Expires:' ),
		'Contact comes before Expires' );
	ok( index( $text, 'Expires:' ) < index( $text, 'Encryption:' ),
		'Expires comes before Encryption' );

	# Many contacts, in the order that the caller named.
	my $many = $kd->security_txt(
		contact => [ 'mailto:a@example.org', 'https://example.org/form' ],
		expires => '2027-01-01T00:00:00Z',
		encryption => [ 'https://example.org/1.asc',
			'https://example.org/2.asc' ],
		languages  => [ 'en', 'sv' ],
	);
	is( scalar( () = $many =~ /^Contact:/mg ), 2, 'two contact fields' );
	is( scalar( () = $many =~ /^Encryption:/mg ), 2, 'two encryption fields' );
	like( $many, qr/^Preferred-Languages: en, sv$/m,
		'the languages join on a comma' );
	ok( index( $many, 'mailto:a@example.org' )
		< index( $many, 'https://example.org/form' ),
		'the contacts keep the order of the caller' );

	is( $kd->security_txt( expires => '2027-01-01T00:00:00Z' ),
		undef, 'an absent contact fails' );
	like( $kd->error, qr/contact is a necessary field/,
		'and the reason says so' );

	is( $kd->security_txt( contact => 'mailto:a@example.org' ),
		undef, 'an absent expiry fails' );
	like( $kd->error, qr/expires is a necessary field/,
		'and the reason says so' );

	# One line holds one field, so an embedded newline would forge
	# a second field.
	is(
		$kd->security_txt(
			contact => "mailto:a\@example.org\nExpires: 1999",
			expires => '2027-01-01T00:00:00Z',
		),
		undef,
		'a value with a newline fails'
	);
	like( $kd->error, qr/holds a newline/, 'and the reason says so' );
};

subtest 'STATUSES names the vocabulary' => sub {
	is_deeply(
		[ Fugu::KeyDir::STATUSES() ],
		[qw(current next retired)],
		'the vocabulary is current, next, retired'
	);
};

done_testing();
