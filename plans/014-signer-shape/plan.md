# 014 — One shape for the three signers

## Status

Proposed. It can land now. FuguWeb WEB-TRUST, WEB-OPENPGP and WEB-X509 wait on
it. The change lands as a minor release: the interface breaks, and no shim keeps
the old one.

Implements: LIB-SIGNER. Extends: LIB-OPENPGP. Extends: LIB-X509.

## Purpose

After the three plans, the three modules drive their commands in three shapes.
The signify signer takes each secret half as a path. The OpenPGP generator
answers the armored secret half as text, and its signer takes it as text. The
X.509 signer takes it as a path, and that module holds no generator. The signify
signer writes a signature file, and the other two answer the signature as a
string. `Fugu::OpenPGP` answers a reason in list context, and `Fugu::Signify`
reports through `error`. Each module resolves its command with a copy of one
resolver, and `Fugu::Curl` holds a fourth.

This plan gives the three modules one shape, one architecture and one security
rule set. One parent class, `Fugu::Signer`, holds what the three share. A
consumer that learns one type then knows the other two.

## Evidence

`Fugu::Signify` verifies over a key set in trust order. When no key verifies, it
names the file and then one reason for each key. That shape serves each type, so
the parent holds the walk and each subclass pins one key in one run.

`Fugu::Signify`, `Fugu::OpenPGP`, `Fugu::X509` and `Fugu::Curl` hold one
`_find_command` each, and they differ in the default list alone. `Fugu::Process`
owns the process boundary, so it owns the resolver.

A secret half that passes through Perl sits in the heap of a long process. A
secret half that a command writes into a private directory, and a rename then
moves, never does. `Fugu::File->atomic_dir` publishes a directory that way, and
the generator takes the same idea for one file.

The tests of `Fugu::X509` make a certificate with openssl(1), and the tests of
FuguWeb WEB-X509 make one too. One generator replaces each shell snippet, and it
gives the third module the same three verbs as the other two.

## The rule changes

### LIB-SIGNER

The unit lands with this plan. It holds the shared shape. The parts are the
constructor and the resolver, the three verbs and their argument names, and the
path rule of a secret half. It also holds the private directory of a generator,
the pinned walk of a verification, the failure convention, `command_absent`, and
the timeout.

### LIB-SIGNIFY

- The unit text states that the module follows LIB-SIGNER over signify(1). It
  takes the same three sentences as the other two units: the type and its files,
  the readers, and the parent.
- The text of LIB-SIGNIFY-2 changes. The `engine` option selects the verifier
  alone: `perl` verifies with `Fugu::Ed25519`, and `signify` runs the command. A
  caller that names a `command` still gets the `signify` engine. `generate` and
  `sign` run the command under both. `is_available` answers 1 under the `perl`
  engine with no command, per LIB-SIGNER-1, because `verify` runs. `command`
  answers the resolved path or undef under both engines, and `command_absent`
  follows LIB-SIGNER-9.
- The rules of the signer and the generator, LIB-SIGNIFY-4 to LIB-SIGNIFY-7,
  change. `new` takes no `keys`. `verify` and `verify_manifest` take `keys` per
  LIB-SIGNER-6, and `generate` takes `comment` beside `public` and `secret`.

### LIB-OPENPGP

- The unit text states that the module follows LIB-SIGNER over gpg(1), in the
  same three sentences.
- The readers become methods of the object, and each one reports through
  `error`, per LIB-SIGNER-8. The text of LIB-OPENPGP-6 keeps the byte rule.
- The rules of the command parts change. `generate` takes `public` and `secret`
  as paths, and it writes the two armored halves there. `sign` and `verify` take
  the names of LIB-SIGNER-2. `expiry` takes `public` as a path. The changed
  generator rule names `email` and an optional `expires`, per LIB-SIGNER-2.
- The text of LIB-OPENPGP-7 changes. The agent of the temporary home follows
  LIB-SIGNER-10.

### LIB-X509

- The unit text states that the module follows LIB-SIGNER over openssl(1), in
  the same three sentences.
- The text of LIB-X509-5 changes. A reader takes bytes, and a command method
  takes paths, per LIB-SIGNER-7.
- A new rule: `generate` takes `subject` and `days`, per LIB-SIGNER-2. They name
  the subject and the validity of the self-signed certificate of LIB-SIGNER-4.
  LIB-SIGNER-5 holds the `public` argument of `sign`.

### LIB-PROCESS

- A new rule: `find_command` resolves a command. A name with a solidus is a
  path, and the method tests that path alone. A plain name walks `PATH`. No name
  walks `PATH` over the default list of the caller. The method answers the path,
  or undef.

### LIB-CURL

- The text of LIB-CURL-1 changes. The module resolves through
  `Fugu::Process->find_command`, and holds no resolver of its own.

## The interface

### Fugu::Signer

- `new(%args)` takes an optional `command` and an optional `timeout`, and each
  subclass adds its own arguments.
- `is_available`, `command`, `command_absent` and `error` follow LIB-SIGNER-1
  and LIB-SIGNER-9.
- `generate(%args)` takes `public` and `secret`, and answers 1 or undef.
- `sign(%args)` takes `secret`, `file` and `signature`, and answers 1 or undef.
- `verify(%args)` takes `keys`, `file` and `signature`, and answers the key path
  or undef.

### Fugu::Signify

- `new` adds `engine`. `generate` adds `comment`.
- `verify_manifest(%args)` takes `keys`, `manifest`, `signature` and `files`.
- The readers `parse_public_key`, `parse_signature`, `parse_manifest` and
  `write_manifest` keep their shape.

### Fugu::OpenPGP

- `generate` adds `email` and an optional `expires`.
- `expiry(%args)` takes `public`, and answers the seconds since the epoch, 0 for
  a key with no expiry, or undef with the reason.
- The readers `decode_armor`, `fingerprint`, `wkd_hash` and `zbase32` become
  methods of the object, and each one reports through `error`.

### Fugu::X509

- `generate` adds `subject` and `days`, and makes a self-signed certificate.
- `sign` adds `public`.
- The readers `decode_pem`, `fingerprint` and `parse` become methods of the
  object, and each one reports through `error`.

### Fugu::Process

- `find_command($name, @defaults)` answers the resolved path, or undef.

## The change

1. `lib/Fugu/Process.pm` and its sidecar gain `find_command`. `lib/Fugu/Curl.pm`
   and `lib/Fugu/Signify.pm` drop their copies. `t/fugu/process.t` covers the
   three forms of a name. `t/fugu/curl.t` and `t/fugu/signify.t` call the new
   method in place of a copy.
2. `lib/Fugu/Signer.pm` and its sidecar hold the parent class. `t/fugu/signer.t`
   covers the shared shape with a stub subclass over a script that the test
   writes. It covers the absent command, `command_absent`, the timeout, and the
   refusal of a path that is no plain file. It also covers the private directory
   of `generate`, and the key walk with its error shape.
3. `lib/Fugu/Signify.pm` and its sidecar inherit the parent. `new` drops `keys`,
   the verifiers take `keys`, and the two engines follow the new text of
   LIB-SIGNIFY-2. `t/fugu/signify.t` follows.
4. `lib/Fugu/OpenPGP.pm` and its sidecar inherit the parent. The readers become
   methods of the object. `generate`, `sign`, `verify` and `expiry` take paths.
   `t/fugu/openpgp.t` follows, and skips when gpg(1) is absent.
5. `lib/Fugu/X509.pm` and its sidecar inherit the parent. The readers become
   methods of the object, `generate` makes a self-signed certificate, and `sign`
   takes `public`. `t/fugu/x509.t` makes its certificate through `generate`, and
   skips when openssl(1) is absent.
6. `lib/Fugu.pod` lists `Fugu::Signer`.
7. `spec/library.md` carries the rule changes, and each of the three unit texts
   takes the same three sentences. `spec/STATUS.md` sets LIB-SIGNER, and keeps
   the other units `done`.
8. This plan directory goes in the same change.

## What this plan does not do

It keeps no old name and no old argument form. A consumer moves to the new shape
when it takes the release, in its own repository. FuguWeb and FuguVM hold
callers of the old shape.

It adds no second engine to `Fugu::OpenPGP` or to `Fugu::X509`. A verifier of an
OpenPGP signature or of a CMS signature in Perl is a larger change than the
need.

It changes no rule of `Fugu::KeyDir`, and no binding name.

It reads no PKCS#12 file, makes no revocation certificate, and checks no chain.
