# The signer modules

This document holds `Fugu::Signer` and the three modules that follow it. The
contract of each library unit is in [library.md](library.md).

<a id="lib-signer"></a>

## Fugu::Signer

One shape for the three modules that drive a signing command: `Fugu::Signify`
over signify(1), `Fugu::OpenPGP` over gpg(1), and `Fugu::X509` over openssl(1).
The module is the parent class of the three. It holds the constructor, the
command resolution, the run through `Fugu::Process`, the key walk of a
verification, and the failure convention. A subclass holds its file formats, its
readers, and the arguments of its command. `Fugu::Signify` also holds its
manifest methods and the `perl` engine.

- **LIB-SIGNER-1** — `new` must take an optional `command` and an optional
  `timeout`. It must resolve the command once, through
  `Fugu::Process->find_command`, and must run no process there. An absent
  command must not die. `is_available` must answer 1 when `verify` can run, and
  0 when it cannot. A subclass with a verifier in Perl then answers 1 with no
  command. `command` must answer the resolved path, or undef. When
  `is_available` answers 0, `error` must hold the reason. Otherwise the first
  method that needs the absent command sets it. A subclass must hold no resolver
  of its own.
- **LIB-SIGNER-2** — The method names must be `generate`, `sign` and `verify` in
  each module, with the argument names `public`, `secret`, `keys`, `file` and
  `signature`. `keys` is a list of paths, and each other one is a path. A
  subclass can add an argument that its type needs, and its unit names it. A
  caller then moves from one type to another with no new vocabulary.
- **LIB-SIGNER-3** — Every private key operation must run in the command. No
  method must take or answer the bytes of a secret half, and the module must
  never log them. A secret half enters as a path and leaves as a file.
  `Fugu::Ed25519` verifies alone, per LIB-ED25519-6.
- **LIB-SIGNER-4** — `generate` must refuse when `public` or `secret` exists,
  and must make a key with no passphrase. The command must write the secret half
  in a private directory beside its destination. The module must set the
  owner-only mode on the file inside that directory. It must then move the file
  into place with one rename. No wider access exists at any moment, and the
  bytes of the secret half never enter Perl. `Fugu::X509` makes a self-signed
  certificate, because a test needs one and no other generator exists.
- **LIB-SIGNER-5** — `sign` must take `secret`, `file` and `signature`, and the
  command must write the signature file itself. A second `sign` over one
  `signature` path must replace the file, because a rotation signs one manifest
  again. `Fugu::X509` must also take `public`, because a PEM private key names
  no certificate.
- **LIB-SIGNER-6** — `verify` must take `keys`, a list of public paths in trust
  order, and must pin one key at a time. It must read no keyring, no home and no
  agent of the user, and must check no chain. It must answer the path of the key
  that verified, or undef. When no key verifies, `error` must name the file and
  then one reason for each key, in one shape across the three modules. An empty
  `keys` list is a programming error, and the method must die.
- **LIB-SIGNER-7** — A command method must take paths. It must refuse an input
  path that is not a plain file before it runs the command. A path of `keys` is
  the exception: a key that does not read is one reason of the walk, per
  LIB-SIGNER-6. `public` and `secret` of `generate` and `signature` of `sign`
  are outputs, per LIB-SIGNER-4 and LIB-SIGNER-5. A reader must take bytes, must
  reject a string with a code point above 255, and must bound the size that it
  reads. Bad bytes are data, so a shape error is a failure with a reason and
  never a die.
- **LIB-SIGNER-8** — Every recoverable failure, of a reader and of a command
  method alike, must return undef, and `error` must hold the reason. No method
  must answer the reason as a second return value. The module never logs, and
  the caller decides what to report.
- **LIB-SIGNER-9** — `command_absent` must report 1 only after a failure in
  which a method needed the command and it never ran. That failure is one of
  two: no command resolved, or the execve(2) failed. It must report 0 after
  every other failure. An install problem and an integrity problem must stay
  apart.
- **LIB-SIGNER-10** — One run of the command must end within `timeout` seconds.
  The default of the parent must be 30, and a subclass can raise it. The unit of
  a subclass that raises it must name its own default. The run must take an
  argument list and never a shell. A run that makes a temporary directory must
  remove it on every exit. It must first stop each helper process that the
  command started under it.
- **LIB-SIGNER-11** — The key walk of `verify` must stop at the first key whose
  run did not start. `error` must then hold that one reason. A failed fork, a
  failed chdir and an absent command give the same answer for every later key.
  Such a failure must not read as "no key verified the signature". A failure of
  the machinery is no integrity failure, per LIB-SIGNER-9.

<a id="lib-openpgp"></a>

## Fugu::OpenPGP

The module follows [Fugu::Signer](#lib-signer) over gpg(1), and it holds the
armored key pair, the detached signature and the expiry of a key. Each reader is
a method of the object: the armor decoder, the key fingerprint, and the Web Key
Directory hash. The parent holds the three verbs, and this unit holds the byte
reader, the temporary home and the expiry.

- **LIB-OPENPGP-1** — The armor decoder must compare the CRC-24 checksum line
  against the decoded bytes. A decoder that skips the comparison accepts a
  truncated key, and a truncated key gives a fingerprint of its own.
- **LIB-OPENPGP-2** — The fingerprint must read the packet length from the
  header and must write the length again. One key then gives one answer in the
  old packet format and in the new one.
- **LIB-OPENPGP-3** — The Web Key Directory hash must use the z-base-32 alphabet
  `ybndrfg8ejkmcpqxot1uwisza345h769`, and must fold the ASCII letters of the
  local part alone. The RFC 4648 alphabet gives a URL that gpg(1) never asks
  for. A fold that reads a byte above 127 rewrites a UTF-8 local part.
- **LIB-OPENPGP-4** — The armor decoder must hold the base64 body to a whole
  number of groups. It must take the padding at the end of the last body line
  only. A reader drops a partial group, and every byte after the padding. Either
  shape gives a truncated key that a crafted checksum line matches.
- **LIB-OPENPGP-5** — The armor decoder must not accept a block that gpg(1)
  rejects. A site publishes the key that this decoder validated, so a consumer
  must be able to import it. The rule runs one way only: the decoder can reject
  a block that gpg(1) reads, and it does so in several places.
- **LIB-OPENPGP-6** — Each method of the decoder must take bytes, and must
  reject a string that holds a code point above 255. `Digest::SHA` dies on such
  a string. A byte unpack takes the low byte of each character, which gives a
  wrong answer in place of a failure.
- **LIB-OPENPGP-7** — Each run of `gpg(1)` must take a temporary home that the
  run removes. The module must read no home of the user, and no agent of the
  user. It must stop the agent of the temporary home before it removes the home,
  per LIB-SIGNER-10. An agent that outlives its home leaks a process.
- **LIB-OPENPGP-8** — `generate` must take `email` beside `public` and `secret`,
  and an optional `expires`, per LIB-SIGNER-2. It must make one Ed25519 key with
  one user id, and one Curve25519 encryption subkey. The user id must hold the
  email alone. The generator must give the key and the subkey the expiry that
  the caller named. It must set no expiry when the caller names none. gpg(1)
  writes each expiry as a duration from a creation time, so the subkey expiry
  can fall one second before the key expiry. FuguWeb WEB-OPENPGP publishes the
  key, and a correspondent encrypts to the subkey.
- **LIB-OPENPGP-9** — `verify` must import the one public key of the walk into
  an empty home, per LIB-SIGNER-6. A signature of another key must fail.
- **LIB-OPENPGP-10** — The module must never log a private half, and must never
  hold its bytes. `generate` and `sign` must name each half as a path, and
  `gpg(1)` must read and write the file itself, per LIB-SIGNER-3. The temporary
  home must hold no group mode and no other mode.
- **LIB-OPENPGP-11** — `expiry` must take `public` as a path, and must answer
  the expiry as seconds since the epoch. It must answer 0 for a key that holds
  no expiry, and undef with the reason for a failure. A caller then tells "no
  expiry" from "cannot read" with one test.
- **LIB-OPENPGP-12** — The default `timeout` must be 60 seconds, per
  LIB-SIGNER-10. A key generation waits for entropy, and it needs the wider
  bound.

<a id="lib-signify"></a>

## Fugu::Signify

The module follows [Fugu::Signer](#lib-signer) over signify(1), and it holds the
key pair, the signature file and the SHA256 manifest. Each reader is a method of
the object: the public key reader, the signature reader, and the manifest
reader. The parent holds the three verbs, and this unit holds the two engines,
the manifest methods and the file formats.

- **LIB-SIGNIFY-1** — The manifest writer must sort its keys, so two runs write
  one byte sequence. It must reject a key that a stricter reader cannot carry. A
  parenthesis ends the key in a reader that stops at the first one. Whitespace
  breaks a reader that splits a line on space.
- **LIB-SIGNIFY-2** — The module must verify with two engines, and the `engine`
  option must name the one to take. The engine must select the verifier alone.
  The `perl` engine must use [Fugu::Ed25519](library-crypto.md#lib-ed25519), and
  it must be the default. The `signify` engine must run the command, and a
  caller that names a `command` must get that engine. `generate` and `sign` must
  run the command under both engines. Under the `perl` engine `is_available`
  must return 1 with no command, per LIB-SIGNER-1, because `verify` runs.
  `command` must answer the resolved path, or undef, under both engines, and
  `command_absent` must follow LIB-SIGNER-9. Both engines must answer the same
  on the same input, and both must write the same error shape.
- **LIB-SIGNIFY-3** — The module must parse a signify(1) public key file and a
  signify(1) signature file. Each file holds a comment line and a base64 body.
  The body holds the two letters `Ed`, an 8-byte key number, and the key or the
  signature. The comment line carries no trust. A key number that differs from
  the signature must give the reason "checked against wrong key". The walk of
  the key set must then continue.
- **LIB-SIGNIFY-4** — `generate` and `sign` must run signify(1) under either
  engine, per LIB-ED25519-6. Perl holds no private key operation. An absent
  command must fail the call, and `command_absent` must report 1, per
  LIB-SIGNER-9.
- **LIB-SIGNIFY-5** — `verify` and `verify_manifest` must take `keys`, per
  LIB-SIGNER-6. `verify_manifest` must also take `manifest`, `signature` and
  `files`, and it must verify the signature before it digests one file. A key of
  `files` is the key of a manifest line, and the module must hold it as text. It
  can be a file name, a file path, or a download URL, and the value is the local
  path to digest.
- **LIB-SIGNIFY-6** — `generate` must take `comment` beside `public` and
  `secret`, and must make a pair with no passphrase, per LIB-SIGNER-4. It must
  reject a comment that holds a newline, before the command runs. The comment
  reaches the first line of each half, so a newline would forge a line of the
  key file.
- **LIB-SIGNIFY-7** — `new` must take no `keys`, and the object must hold no key
  set. One object must serve the generator, the signer, the verifier and the
  manifest readers.

<a id="lib-x509"></a>

## Fugu::X509

The module follows [Fugu::Signer](#lib-signer) over openssl(1), and it holds the
self-signed certificate, the private key and the detached CMS signature. Each
reader is a method of the object: the PEM decoder, the certificate fingerprint,
and the reader of the names and the validity. The parent holds the three verbs,
and this unit holds the byte reader and the DER walk.

- **LIB-X509-1** — The reader must take the subject, the issuer, `notBefore` and
  `notAfter` from the DER itself, with no command. A fingerprint check and an
  expiry check then run where openssl(1) is absent.
- **LIB-X509-2** — The fingerprint must be the SHA-256 of the DER bytes, in
  upper-case hexadecimal with no separator. Other tools print the leaf hash in
  that form.
- **LIB-X509-3** — A signature must be a detached CMS signature. The verifier
  must pin the one certificate that the caller names, and must check no chain.
  The caller vouches for the certificate by other means.
- **LIB-X509-4** — The module must hold no issuer by name. A code signing
  certificate of Apple Developer ID is one use, and the module treats every
  issuer the same way.
- **LIB-X509-5** — A reader must take bytes, and a command method must take
  paths, per LIB-SIGNER-7. A reader must reject a string with a code point above
  255, as LIB-OPENPGP-6 holds for the OpenPGP reader.
- **LIB-X509-6** — The PEM decoder must take one `CERTIFICATE` block, and must
  reject a private key block and a second block. A key directory publishes what
  the decoder accepts.
- **LIB-X509-7** — `generate` must take `subject` and `days` beside `public` and
  `secret`, per LIB-SIGNER-2. They name the subject and the validity of the
  self-signed certificate of LIB-SIGNER-4. LIB-SIGNER-5 holds the `public`
  argument of `sign`.
- **LIB-X509-8** — The default `timeout` must be 300 seconds, per LIB-SIGNER-10.
  A signature reads the whole file, and a file of a few hundred megabytes needs
  the wider bound.
