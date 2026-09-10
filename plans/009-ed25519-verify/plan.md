# 009 — Ed25519 verification in core Perl

## Status

Proposed. Both parts can land now, in one change. The module compiles under
either floor, so the order against plan 008 does not matter.

Implements: LIB-ED25519.

Extends: LIB-SIGNIFY. The implementation adds the engine rule to that unit and
lands the rule with the code.

## Purpose

`Fugu::Signify` verifies a signature by running signify(1). The command sits in
the base system of OpenBSD, and nowhere else. A Linux host installs the package
`signify-openbsd`, and a macOS host installs `signify-osx` through Homebrew.
Each consumer manifest names that package in its `tool` environment, and a host
without it cannot verify a release.

This plan adds `Fugu::Ed25519`, a module that verifies an Ed25519 signature with
core Perl alone. It gives `Fugu::Signify` a second engine that uses the module,
and it makes that engine the default. A consumer then verifies a signify(1)
signature on every host, with no command installed. The signify(1) engine stays,
for a caller that wants the command.

## Why Fugu holds this work

The key set, the trust order, the manifest parser, and the error shape live in
`Fugu::Signify` already. The math is generic, and no consumer policy sits in it.
FuguBench packs Fugu into one file, so a module here reaches the bootstrap of
every repository. The synced `scripts/deps` cannot load Fugu (Tooling
SYNC-DOWNLOAD-8), and FuguBench removes that limit through the pack.

## Consumers

| Repo      | Need                                                                  |
| --------- | --------------------------------------------------------------------- |
| FuguBench | Verify a signed release manifest with no signify(1) on the host       |
| FuguWeb   | Drop the signify package from the `tool` environment of two manifests |
| FuguVM    | Verify a release set on a Linux or a Darwin host without the package  |
| Tooling   | None. `scripts/deps` stays core-only, until FuguBench replaces it     |

## Scope

In scope:

- `Fugu::Ed25519`: the field arithmetic, the point decoder, and the check of
  RFC 8032.
- `Fugu::Signify`: the parsers of a signify(1) public key and signature, and the
  `engine` option.
- The fixtures, the tests, and the two `.pod` sidecars.

Out of scope:

- Signing, and key generation. A signature is a human act, and signify(1) makes
  it.
- An embedded signature, which signify(1) makes with `-e`, and a gzip signature,
  which it makes with `-z`. The organization signs detached manifests only.
- A constant-time implementation. Every input of a verification is public.
- A change in a consumer manifest. Each consumer drops its package in a change
  of its own.

## Constraints that shape the design

**The signify(1) formats are two lines each.** A public key file holds a comment
line and a body line. The comment line starts with `untrusted comment: `, and it
carries no trust. The body is the base64 of 42 bytes: the letters `Ed`, an
8-byte key number, and the 32-byte public key. A signature file has the same
shape. Its body is the base64 of 74 bytes: `Ed`, the same key number, and the
64-byte signature. The signature covers the bytes of the signed file. The key
number binds a signature to a key, and signify(1) reports a mismatch as "checked
against wrong key".

**The math fits core Perl.** The field is the integers modulo `2^255 - 19`, and
`Math::BigInt` holds them. The check needs one modular square root to decode a
point, and two scalar multiplications. That is about four thousand field
multiplications. The pure-Perl backend `Math::BigInt::Calc` takes about one
second for one check. `Math::BigInt::GMP` takes milliseconds, and the line
`use Math::BigInt try => 'GMP,Pari'` picks it when the host has it, with no
dependency. `Digest::SHA` holds SHA-512, and `MIME::Base64` decodes the files.
All three are core, so ARC-COREPERL-1 holds with no lazy `require`.

**A verification needs no constant time.** The key, the signature, and the
message are public. A timing side channel tells an attacker nothing new. The
module signs nothing, so no secret ever enters it.

**The message streams.** The check hashes the concatenation of the point `R`,
the key `A`, and the message. `Digest::SHA` takes the first two as bytes and
then reads the file, so a message of any size needs no memory.

**Shape errors and math failures differ.** A key or a signature of the wrong
length is a programming error of the caller. So is a string with a character
above 255. The method returns undef and names the reason. A well-shaped
signature that fails the check is a signature that does not verify. So is a
scalar at or above the group order, and a point encoding that decodes to no
point. The method returns 0. A caller then tells "the caller gave bad input"
from "the file is not authentic".

**The object keeps its contract.** Every method of `Fugu::Signify` keeps its
behavior under the signify(1) engine. The default engine changes to `perl`. A
caller that names a `command` asks for the command, so that call defaults to the
signify(1) engine.

**The caller rule.** ARC-CALLERS-1 states that every sub in `lib/` must have a
caller in `lib/` or in a test. Each sub of this plan gets a test.

## The interface contract

### Fugu::Ed25519

`Fugu::Ed25519->new` builds a verifier with no arguments. The object holds the
reason of the last failure only.

`verify(%args)` takes `key` as 32 bytes, `signature` as 64 bytes, and one of
`message` as bytes or `file` as a path. It returns 1 for a signature that
verifies, 0 for one that does not, and undef for a shape error. `error` holds
the reason after undef.

### Fugu::Signify

`new` gains the option `engine`, with the values `perl` and `signify`. The
default is `perl`. With a `command` argument the default is `signify`. Under the
`perl` engine, `is_available` returns 1, `command` returns undef, and
`command_absent` returns 0.

`parse_public_key($bytes)` returns a hash reference with `comment`, `keynum`,
and `key`, or undef with the reason. It holds the body to 56 base64 characters
that decode to 42 bytes with the prefix `Ed`. The org pack applies the same rule
to `deps/KEYS.txt`.

`parse_signature($bytes)` returns a hash reference with `comment`, `keynum`, and
`signature`, or undef with the reason. It holds the body to 100 base64
characters that decode to 74 bytes with the prefix `Ed`.

`verify($file, $sigfile)` under the `perl` engine reads the signature file under
a bound of 4 KiB and parses it. For each key file in trust order, it reads and
parses the key. A key whose number differs gives the reason "checked against
wrong key", and the loop continues. A key whose number matches runs
`Fugu::Ed25519->verify` with the file. A pass returns the key path. A fail gives
the reason "signature verification failed", and the loop continues. When no key
passes, `error` names the file and each key with its reason, in the shape that
the signify(1) engine writes today.

`verify_manifest` changes nothing. It calls `verify`, so both engines serve it.

## Files

| File                       | Change                                                      |
| -------------------------- | ----------------------------------------------------------- |
| `lib/Fugu/Ed25519.pm`      | New: the verifier                                           |
| `lib/Fugu/Ed25519.pod`     | New: the API contract                                       |
| `lib/Fugu/Signify.pm`      | The `engine` option, the two parsers, the `perl` path       |
| `lib/Fugu/Signify.pod`     | The option, the parsers, and the two engines                |
| `t/fugu/ed25519.t`         | New: the tests of `Fugu::Ed25519`                           |
| `t/fugu/signify.t`         | The tests of the `perl` engine and of the parsers           |
| `t/fugu/signify-a.pub`     | New: a fixture key, made once with signify(1)               |
| `t/fugu/signify-b.pub`     | New: a second fixture key, with another key number          |
| `t/fugu/signify-a.msg`     | New: a fixture message                                      |
| `t/fugu/signify-a.msg.sig` | New: the signature of the message under key a               |
| `spec/library.md`          | The engine rule of `LIB-SIGNIFY`                            |
| `spec/STATUS.md`           | The `LIB-ED25519` row to `done`, and the `LIB-SIGNIFY` note |

## Tests

The operator makes the fixtures once with signify(1) and commits them. No test
runs signify(1) to make a fixture. A test that runs the command engine skips
when the command is absent.

`t/fugu/ed25519.t` covers:

- The five vectors of RFC 8032 section 7.1. The messages are the empty message,
  one byte, two bytes, 1023 bytes, and the SHA-512 digest of `abc`. Each one
  verifies.
- Each vector with one flipped bit in the signature, which returns 0.
- Each vector with one flipped bit in the message, which returns 0.
- A signature whose scalar is at or above the group order, which returns 0.
- A signature whose point encoding decodes to no point, which returns 0.
- A key of 31 bytes, a signature of 65 bytes, and a message with a character
  above 255. Each one returns undef with a reason.
- The `file` form against the `message` form, over one message of 1 MiB. Both
  give the same answer.

`t/fugu/signify.t` gains:

- `parse_public_key` and `parse_signature` on each fixture. Both on a body of
  the wrong length, a body with a wrong prefix, and a file with one line. Each
  bad input returns undef with a reason.
- The `perl` engine verifies the fixture message under key a.
- The `perl` engine with key b alone fails, and the reason names the wrong key.
- The `perl` engine with a modified copy of the message fails, and the reason
  names the failed signature.
- The trust order: the key set `b, a` returns the path of key a.
- `is_available` returns 1 under the `perl` engine with an empty `PATH`.
- Every test of the signify(1) engine keeps its assertions, under
  `engine => 'signify'`, and it skips when the command is absent.
- When the command is on `PATH`, both engines give one answer on the fixture and
  on the modified copy.

## Acceptance

- `make check` passes.
- Each new sub has a caller in a test, per ARC-CALLERS-1.
- Each new module has a `.pod` sidecar and a test, per ARC-NAMESPACES-3.
- `t/fugu/coreperl.t` loads `Fugu::Ed25519` with the pruned `@INC`.
- The `LIB-ED25519` row is `done`, and `LIB-SIGNIFY` holds the engine rule.
- No test makes a fixture with signify(1).
- The change deletes this plan.

## Open questions

None. The operator asked for the module and for the default on 2026-09-10.
