# The cryptography modules

This document holds the Ed25519 verifier, the key directory, and the random
source. The contract of each library unit is in [library.md](library.md).

<a id="lib-ed25519"></a>

## Fugu::Ed25519

Verify an Ed25519 signature with core Perl. The module holds the field
arithmetic over `Math::BigInt`, the point decoder, and the check of RFC 8032. It
signs nothing, and it makes no key. `Fugu::Signify` uses it to verify a
signify(1) signature on a host without the command.

- **LIB-ED25519-1** — The module must verify with core modules only:
  `Math::BigInt` for the field arithmetic, and `Digest::SHA` for SHA-512. It
  must add no CPAN module, so ARC-COREPERL-1 holds with no lazy `require`.
- **LIB-ED25519-2** — `verify` must take a 32-byte public key, a 64-byte
  signature, and the message. The message is a byte string or a file path. A
  file must stream through the hash, so a large file needs no memory.
- **LIB-ED25519-3** — The module must reject a key or a signature of another
  length, and a string that holds a code point above 255. `Digest::SHA` dies on
  such a string, and a byte unpack would give a wrong answer in place of a
  failure.
- **LIB-ED25519-4** — The check must follow section 5.1.7 of RFC 8032. A scalar
  at or above the group order is a signature that does not verify. So is a point
  encoding that decodes to no point. Such an encoding is not canonical, and two
  encodings of one signature would let a signature count twice.
- **LIB-ED25519-5** — `verify` must return 1 for a signature that verifies, and
  0 for one that does not. A shape error is a failure: the method returns undef,
  and `error` holds the reason. A caller then tells bad input from a file that
  is not authentic.
- **LIB-ED25519-6** — The module must hold no private key operation. It must not
  sign, and it must not derive a key. A private key operation stays with
  signify(1), which the signer of `Fugu::Signify` runs.
- **LIB-ED25519-7** — The module must let `Math::BigInt` take a faster backend
  when the host has one, and it must run with the pure-Perl backend alone. One
  check takes about one second with that backend, so a caller runs a few checks,
  and never a stream.

<a id="lib-keydir"></a>

## Fugu::KeyDir

The names, the order and the generated text of a published key directory. It
holds the key name pattern `<org>-<serial>-<purpose>.<ext>`, the type from the
extension, and the status vocabulary. It also holds the order of a key set. It
holds the text of the Apache `KEYS` file, of the human index, and of
`security.txt`. It holds the name of a binding, and the retention rule of a set
of bindings. A binding is the signature of one key file by another key.

- **LIB-KEYDIR-1** — The publication order must be total: `current`, then
  `next`, then `retired`, and inside one status the serial must descend. A site
  build writes the index page on every build, so an unstable order would make a
  diff on each run.
- **LIB-KEYDIR-2** — Each purpose must hold exactly one `current` key, and at
  most one `next` key. A purpose with two `current` keys names no key in force,
  so a reader cannot tell which key signs a release.
- **LIB-KEYDIR-3** — The module must hold no organization word, no purpose list,
  and no contact as a constant, and must not render markup. Each one is an
  argument, and the site owns the template.
- **LIB-KEYDIR-4** — The generated text must let no caller field forge a field
  or a block. A value that reaches a one-field line must hold no newline. A
  value that a list joins must hold no separator. An armored body must hold one
  block with no text outside it. `gpg --import` reads the `KEYS` file, so a
  forged block would publish a second key under one name.
- **LIB-KEYDIR-5** — The binding name must be
  `<target file>.<signer stem>.<ext>`. The extension must follow the type table
  of the module: `sig` for a signify signer, and `asc` for an OpenPGP signer. An
  X.509 signer takes `p7s`, and an X.509 key file takes `pem`. A later type adds
  its own extension. The parser and the builder must stay inverses. The parser
  must answer the signer as a key file name. Those parts must feed the builder,
  and must name the same file. The extension table must stay in the module, so a
  writer and a reader name one file, and no caller holds a second copy.
- **LIB-KEYDIR-6** — The retention rule must hold each binding of a directory. A
  signer that is `current` or `next` must target the root key. A signer that is
  `retired` must target a key of its own purpose with a higher serial. The
  caller names the root key, per LIB-KEYDIR-3.

<a id="lib-random"></a>

## Fugu::Random

Random bytes and random passwords, from `/dev/urandom`.
