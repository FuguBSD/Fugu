# 007 — The key directory: names, OpenPGP keys, and the manifest writer

## Status

Proposed.

## Purpose

A FuguBSD site publishes the public keys of the organization. The generic parts
of that key directory belong in Fugu, so a site build, FuguVM, and a future tool
share one tested implementation.

This plan adds two modules and it extends one:

- `Fugu::KeyDir` holds the key name pattern, the type of a key, the status
  vocabulary, the order of a key set, and the text of each generated file.
- `Fugu::OpenPGP` decodes an armored OpenPGP key, computes the v4 fingerprint,
  and computes the Web Key Directory hash of a local part.
- `Fugu::Signify` gains a public manifest parser and a manifest writer.

No module runs gpg(1) or signify(1). Each one reads and writes bytes and text
only.

## Why Fugu holds this work

FuguBSD/Website publishes the keys, and FuguBSD/FuguWeb builds that site. A site
build is an application, so the generic parts must not live there. The
organization decided this in the workspace plan: the generic parts of the key
directory live in Fugu modules, and FuguWeb holds the site wiring only.

Three consumers need the same answers. FuguWeb generates the key directory of
each site. The rotation workflow of Website writes a signed `SHA256` manifest,
and it needs the same manifest form that a consumer install reads. A consumer
install reads `deps/KEYS.txt` and verifies a release, and `scripts/deps` holds
its own copy of the digest logic, because it is the bootstrap.

The work is a set of low-level utilities. A key name is a string pattern. An
armored key is a base64 block with a checksum. A fingerprint is a SHA-1 over a
packet. None of it is policy, and none of it needs a command.

## Consumers and citations

| Repo    | Unit                       | Need                                                                     |
| ------- | -------------------------- | ------------------------------------------------------------------------ |
| FuguWeb | the `keys` block of a site | Read the description blocks, call these modules, and write the tree      |
| Website | the rotation workflow      | Write `keys/SHA256` with the same manifest form that a consumer reads    |
| Tooling | `scripts/deps`             | Read a signed manifest. The bootstrap holds its own copy, and stays core |

## Scope

This plan adds the generic parts only.

In scope:

- The key name pattern, and the parts of a name.
- The type of a key, from its extension.
- The status vocabulary, and the rule of one `current` key for each purpose.
- The order of a key set.
- The text of `KEYS`, the index data, and `security.txt`.
- The armor decoder, the v4 fingerprint, and the Web Key Directory hash.
- The public manifest parser, and the manifest writer.

Out of scope:

- The `.fuguwebrc` grammar of the `keys` block. FuguWeb owns it.
- The output tree, the copy steps, and the `fuguweb check` rules. FuguWeb owns
  them.
- Any run of gpg(1) or signify(1) to make a key or a signature.
- The publication itself, and the rotation workflow. Website owns them.

## Constraints that shape the design

**The load contract.** ARC-COREPERL-1 states that Fugu loads with core Perl
only. Each module of this plan uses `Digest::SHA` and `MIME::Base64`, and both
are core. No lazy `require` is needed.

**A signify public key is one line.** A signify public key file holds two lines.
The first line starts with `untrusted comment: `, and signify(1) rejects a file
without that prefix. The second line is the key body: 42 bytes in base64, 56
characters, and the first two bytes spell `Ed`. The comment carries no trust.

**An armored OpenPGP key holds a checksum.** The armor of RFC 4880 holds a
base64 block, then a line that starts with `=` and holds the CRC-24 of the
decoded bytes. A decoder that skips the checksum accepts a truncated key.

**The v4 fingerprint reads the packet, not the armor.** The fingerprint is the
SHA-1 of `0x99`, the two-byte length of the public key packet body, and that
body. The armor holds the packet in the old format, with a one-byte length or a
two-byte length. The decoder must read both.

**The Web Key Directory hash is not the fingerprint.** The hash is the z-base-32
form of the SHA-1 of the local part, in lower case. The alphabet is
`ybndrfg8ejkmcpqxot1uwisza345h769`, and it is not the RFC 4648 alphabet.

**The caller rule.** ARC-CALLERS-1 states that every sub in `lib/` must have a
caller in `lib/` or in a test. Each sub of this plan gets a test.

**Genericity.** ARC-GENERIC states that no consumer policy lives here. The
organization word, the purposes, the contact and the dates are arguments. The
modules hold the pattern and the vocabulary only.

## The interface contract

### Fugu::KeyDir

`Fugu::KeyDir` is a class. `new(org => $word)` builds a directory. The
organization word is necessary, and `new` dies without it.

#### parse_name

`parse_name($filename)` splits a key file name into its parts. It returns a hash
reference with `stem`, `org`, `serial`, `purpose` and `type`, or `undef` with
the reason in `error`.

The pattern is `<org>-<serial>-<purpose>.<ext>`. The organization word must
equal the word of the object. The serial must be an integer with no padding and
above zero. The purpose must hold lower-case letters, digits and hyphens. The
extension selects the type: `pub` is `signify`, and `asc` is `openpgp`.

#### name_for

`name_for(serial => $n, purpose => $word, type => $type)` returns the file name
of a key. The method is the inverse of `parse_name`, so a caller never builds a
name by hand.

#### next_serial

`next_serial(\@names, $purpose)` returns the serial that a rotation of that
purpose must take. It is one above the highest serial of the purpose, and it is
1 when no key of the purpose exists.

#### order

`order(\@keys)` returns the keys in publication order. A key is a hash reference
with the parts of its name and its `status`. The order is `current`, then
`next`, then `retired`. Inside one status the order is the serial, in descending
order. The order is total, so two runs write one byte sequence.

#### check_statuses

`check_statuses(\@keys)` holds a key set to the status rule. Each purpose must
hold exactly one `current` key, and at most one `next` key. The method returns 1
on a pass, and `undef` with the reason in `error` on a failure.

#### keys_file

`keys_file(\@keys)` returns the text of the Apache `KEYS` file. It holds each
OpenPGP key of the set, in publication order, with a comment block in front of
each armored body. It skips a signify key: `gpg --import` reads this file.

#### index_data

`index_data(\@keys)` returns the data of the human page, as an array reference
of hash references in publication order. Each one holds the serial, the purpose,
the type, the fingerprint, the status and the dates. The method renders no HTML:
the site owns the template.

#### security_txt

`security_txt(%args)` returns the text of `security.txt`, per RFC 9116. It holds
a `Contact` field, an `Expires` field, and an `Encryption` field for each key
that the caller names. The method writes the fields in the order of the RFC.

#### The status vocabulary

`STATUSES` is the list `current`, `next`, `retired`. A status outside the list
is a failure that names the status.

### Fugu::OpenPGP

`Fugu::OpenPGP` holds class methods only. It builds no object, because it holds
no state.

#### decode_armor

`decode_armor($text)` returns the binary form of an armored block, or `undef`
with the reason. It reads the two delimiter lines, it skips the armor headers,
it decodes the base64 body, and it compares the CRC-24 checksum line against the
decoded bytes. A missing delimiter, a bad base64 body, an absent checksum, and a
checksum mismatch are each a failure.

#### fingerprint

`fingerprint($binary)` returns the v4 fingerprint of the first public key
packet, in upper-case hexadecimal with no separator. It returns `undef` with the
reason for a first packet that is not a public key packet, and for a packet
version that is not 4.

#### wkd_hash

`wkd_hash($local_part)` returns the Web Key Directory hash of a local part. It
lowercases the part, it takes the SHA-1, and it encodes the digest in z-base-32.

#### zbase32

`zbase32($bytes)` encodes bytes in z-base-32. `wkd_hash` calls it, and a caller
can call it for another purpose.

### Fugu::Signify

Two additions. Every method that exists keeps its behavior.

#### parse_manifest

`parse_manifest($bytes)` is the public form of the parser that `verify_manifest`
already uses. It returns a hash reference of manifest key to lower-case digest,
or `undef` with the reason in `error`.

The rotation workflow and the site check both read a manifest, and neither one
verifies a signature at that moment. A private parser would make each caller
write the line form again.

#### write_manifest

`write_manifest(\%digests)` returns the text of a `SHA256` manifest. Each line
holds `SHA256 (key) = digest`, and the keys sort in ascending order, so two runs
write one byte sequence. The method returns `undef` with the reason for an empty
hash, for a key that holds a parenthesis or a space, and for a digest that is
not 64 hexadecimal characters.

The key of a line is a file name, a file path, or a download URL, as
`_parse_manifest` already states. The writer therefore accepts any of the three,
and it rejects only a key that the line form cannot hold.

### What the modules must not hold

- No run of gpg(1), of signify(1), or of any command.
- No private key, and no signing.
- No network request.
- No HTML template, and no site layout.
- No organization word, no purpose list, and no contact as a constant.

## Load contract

`Fugu::KeyDir` uses `Digest::SHA` and `Fugu::OpenPGP`. `Fugu::OpenPGP` uses
`Digest::SHA` and `MIME::Base64`. Both are core, so ARC-COREPERL-1 holds with no
lazy `require`.

The bootstrap rule of Tooling does not reach these modules. Only the synced
scripts must stay core-only, and `scripts/deps` holds its own copy of the digest
logic for that reason.

## Files

| File                         | Change                                           |
| ---------------------------- | ------------------------------------------------ |
| `lib/Fugu/KeyDir.pm`         | New: the key directory module                    |
| `lib/Fugu/KeyDir.pod`        | New: the API contract                            |
| `lib/Fugu/OpenPGP.pm`        | New: the OpenPGP module                          |
| `lib/Fugu/OpenPGP.pod`       | New: the API contract                            |
| `lib/Fugu/Signify.pm`        | `parse_manifest` and `write_manifest`            |
| `lib/Fugu/Signify.pod`       | The two new methods                              |
| `t/fugu/keydir.t`            | New: the tests of `Fugu::KeyDir`                 |
| `t/fugu/openpgp.t`           | New: the tests of `Fugu::OpenPGP`                |
| `t/fugu/openpgp-ed25519.asc` | New: a fixture key with a one-byte packet length |
| `t/fugu/openpgp-rsa.asc`     | New: a fixture key with a two-byte packet length |
| `t/fugu/signify.t`           | The tests of the two new methods                 |
| `spec/library.md`            | The `LIB-KEYDIR` and `LIB-OPENPGP` units         |
| `spec/STATUS.md`             | One row for each new unit                        |

## Tests

The fixtures are two armored OpenPGP public keys, committed as files. A test
must not run gpg(1), because the build must not need the command. One fixture is
an Ed25519 key, whose packet takes a one-byte length. The other is an RSA 3072
key, whose packet takes a two-byte length. Both length paths therefore get a
real key.

`t/fugu/openpgp.t` covers:

- `decode_armor` on each fixture, and the length of the binary form.
- `decode_armor` on a body with a corrupt checksum line, which must fail.
- `decode_armor` on a block with no end delimiter, which must fail.
- `fingerprint` on each fixture, against the fingerprint that gpg(1) reports.
- `fingerprint` on a first packet that is not a public key packet.
- `wkd_hash` against the two published vectors of the Web Key Directory draft:
  `Joe.Doe` gives `iy9q119eutrkn8s1mk4r39qejnbu3n5q`, and `bernhard.reiter`
  gives `it5sewh54rxz33fwmr8u6dy4bbz8itz4`.
- `wkd_hash` on a mixed-case local part, which must equal the lower-case answer.
- `zbase32` on the empty string, and on a byte count that is not a multiple of
  five.

`t/fugu/keydir.t` covers:

- `parse_name` on a valid name of each type.
- `parse_name` on a wrong organization word, a padded serial, a zero serial, an
  unknown extension, and a purpose with an upper-case letter. Each one fails.
- `name_for`, and the round trip through `parse_name`.
- `next_serial` on an empty list, on one purpose, and on two purposes.
- `order` on a set with each status, and the descending serial inside a status.
- `check_statuses` on a valid set, on a purpose with two `current` keys, on a
  purpose with two `next` keys, and on a purpose with no `current` key.
- `keys_file`, and that it holds no signify key.
- `index_data`, and its order.
- `security_txt`, and the field order.

`t/fugu/signify.t` gains:

- `parse_manifest` on a valid manifest, on an empty one, on a bad line, on a
  short digest, and on a duplicate key.
- `write_manifest` on a valid hash, and that the output sorts by key.
- `write_manifest` on an empty hash, on a key with a parenthesis, on a key with
  a space, and on a bad digest. Each one fails.
- A round trip: `write_manifest` then `parse_manifest` returns the input hash.

## Acceptance

- `make check` passes.
- Each new sub has a caller in a test, per ARC-CALLERS-1.
- Each new module has a `.pod` sidecar and a test, per ARC-NAMESPACES-3.
- `spec/library.md` holds `LIB-KEYDIR` and `LIB-OPENPGP`, and `spec/STATUS.md`
  holds one row for each.
- No module of this plan runs a command, and no test needs gpg(1) or signify(1).
- The change deletes this plan.

## Open questions

None. The design of this plan comes from the workspace plan, which the operator
approved. The two alternatives that the workspace plan rejected stay rejected: a
chain of trust that lets one key mint a successor, and a rotation that switches
a key with no human review.
