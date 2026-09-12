# The library

One module holds one concern. This document names each module and its concern.
The API contract of a module lives in its `.pod` sidecar. A unit below carries
rules only where the design needs a requirement beyond the sidecar.

<a id="lib-cli"></a>

## Fugu::CLI

Subcommand dispatch for a command-line tool.

<a id="lib-config"></a>

## Fugu::Config

The OpenBSD-style configuration grammar.

<a id="lib-control"></a>

## Fugu::Control

A control socket for a running daemon, with its client.

- **LIB-CONTROL-1** — A `mode` option and a `group` option on `listen` must set
  the socket mode and group. The socket must never accept a wider set of users
  than the final set. FuguTTX HRN-SOCKET names such a socket: group `ttxop`,
  mode `0660`, and membership as the operator grant.
- **LIB-CONTROL-2** — The server must report the peer credentials of the
  connection that a handler answers. It must read them once per connection with
  `SO_PEERCRED`, in the `struct sockpeercred` field order, on OpenBSD alone. A
  companion predicate must tell "not supported" from "the read failed". FuguTTX
  HRN-SOCKET names the read, and FuguTTX HRN-CONFIRM-6 names the peer user id
  that gates a confirmation.

<a id="lib-curl"></a>

## Fugu::Curl

Download one URL to one file through the downloader that the host has: `curl`
first, then `wget`, then the `ftp` of OpenBSD. The module runs the command
through `Fugu::Process`, with an argument list and never a shell. A consumer
that ships a shell helper over the same three commands replaces it with this
module.

- **LIB-CURL-1** — The module must resolve its command through
  `Fugu::Process->find_command`, per LIB-PROCESS-5, over the default list
  `curl`, `wget`, `ftp`. It must hold no resolver of its own. A caller can name
  a command, as a plain name or as a path. The base name of the resolved command
  must be one of the three, because each dialect has its own flag set. Another
  name resolves nothing, and `error` must hold the reason. The module must
  resolve the command once, in `new`, and it must run no process there.
- **LIB-CURL-2** — A fetch must verify the TLS certificate of the peer. The
  module must pass no option that turns the check off.
- **LIB-CURL-3** — A fetch must follow a redirect, and it must fail on an HTTP
  status of 400 or above. Without its fail flag, `curl` exits zero on such a
  status and writes the error page as the file.
- **LIB-CURL-4** — A failed fetch must leave no file at the destination. The
  module must write to a temporary name in the destination directory, and it
  must rename the file on success. The rename is atomic, so a reader never sees
  a partial file.
- **LIB-CURL-5** — The result must tell the failures apart as far as the command
  reports them. `status` must hold one of `http`, `network`, `timeout`, and
  `absent`. The module must read the HTTP status where the command gives one,
  and `code` must hold it. A status of 400 or above must give `http`. The module
  must give `timeout` when its own bound fires, or when the command reports a
  timeout. The module must give `absent` when it resolved no command, or when
  the command never ran. Every other failure must take `network`. A caller that
  probes for an optional file then reads a 404 as the normal answer.
- **LIB-CURL-6** — A `timeout` option must bound the whole fetch, with a default
  of 600 seconds. A release asset on a slow link needs minutes, and a stalled
  connection must not hold a bootstrap forever.
- **LIB-CURL-7** — The module must pass the proxy variables of the environment
  to the command: `http_proxy`, `https_proxy`, `ftp_proxy`, and `no_proxy`. A
  host behind a proxy reaches a release through them.
- **LIB-CURL-8** — The command must run quietly. It must write no progress
  meter, and it must write a diagnostic on failure only. The module returns the
  diagnostic in `error`, with the command name and the URL.
- **LIB-CURL-9** — Every recoverable failure must return undef, and `error` must
  hold the reason. The module never logs, and the caller decides what to report.

<a id="lib-daemon"></a>

## Fugu::Daemon

Daemonization for Perl programs.

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

<a id="lib-eventloop"></a>

## Fugu::EventLoop

One select loop for a daemon with one process.

<a id="lib-file"></a>

## Fugu::File

File operations for a daemon and its tools.

<a id="lib-imsg"></a>

## Fugu::Imsg

imsg messages over a connected stream socket. The frame bytes come from
`Protocol::Imsg` (LIB-PROTOCOL).

<a id="lib-jsonsocket"></a>

## Fugu::JSONSocket

Newline-delimited JSON over a UNIX socket.

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

<a id="lib-log"></a>

## Fugu::Log

Logging to syslog, standard error, or nowhere.

- **LIB-LOG-1** — In syslog mode, the logger must give the `syslog_method` list
  to `setlogsock` before it opens the log. A failed pin must die at the open. An
  empty list is the one exception: it pins nothing, and `Sys::Syslog` keeps its
  own order.
- **LIB-LOG-2** — A `syslog_method` option on `new` must select the syslog
  transport, as one mechanism name or a list, with the default `native`. An
  accessor of the same name must report the list, so a caller audits the
  transport. The default is the native method that FuguTTX HRN-SAFE-AUDIT pins
  for the pledged daemon; the option serves a host with no working native
  transport.

<a id="lib-mqtt"></a>

## Fugu::MQTT

A subscribing MQTT client for a single-threaded daemon. An optional feature: the
module requires `Net::MQTT::Simple` lazily.

<a id="lib-mdnsd"></a>

## Fugu::Mdnsd

Control mdnsd(8) over its control socket. The client implements publish only.
The wire protocol is in [protocol/MDNS-Control.md](protocol/MDNS-Control.md).

<a id="lib-openpgp"></a>

## Fugu::OpenPGP

An armored OpenPGP public key as bytes, and gpg(1) over a key. The module holds
a byte reader and a command part. The byte reader holds the armor decoder and
the version 4 fingerprint of a public key packet. It also holds the Web Key
Directory hash of an email local part. It runs no command, and it holds class
methods only. The command part runs `gpg(1)` through an object. The object
generates a key and exports both halves. It makes a detached signature, it
verifies one, and it reads the expiry of a key. `new` resolves the command once,
and it never dies for an absent command.

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
  user. It must kill the agent of the temporary home before it removes the home,
  because an agent that outlives its home leaks a process.
- **LIB-OPENPGP-8** — The generator must make one Ed25519 key with one user id,
  and one Curve25519 encryption subkey. The user id must hold the email alone.
  The generator must give the key and the subkey the expiry that the caller
  named. It must set no expiry when the caller names none. gpg(1) writes each
  expiry as a duration from a creation time, so the subkey expiry can fall one
  second before the key expiry. FuguWeb WEB-OPENPGP publishes the key, and a
  correspondent encrypts to the subkey.
- **LIB-OPENPGP-9** — The verifier must import the one public key of the signer
  into an empty home. A signature of another key must fail.
- **LIB-OPENPGP-10** — The module must never log the armored secret half, and
  must never write it to a file of its own. It must pass each secret half to
  `gpg(1)` on the standard input. The temporary home must hold no group mode and
  no other mode.
- **LIB-OPENPGP-11** — `expiry` must answer the expiry as seconds since the
  epoch. It must answer 0 for a key that holds no expiry, and undef with the
  reason for a failure. A caller then tells "no expiry" from "cannot read" with
  one test.

<a id="lib-pidfile"></a>

## Fugu::Pidfile

A locked PID file.

<a id="lib-privdrop"></a>

## Fugu::Privdrop

Permanent drop of root privileges.

<a id="lib-process"></a>

## Fugu::Process

Child process management.

- **LIB-PROCESS-1** — An `env` option must give a child a fixed `%ENV`.
- **LIB-PROCESS-2** — A `group` option on `terminate` must kill the process
  group of the child.
- **LIB-PROCESS-3** — An `inherit` option on `spawn_command` and `spawn_peer`
  must name the descriptors that a child keeps across the exec, each at its own
  number. FuguTTX HRN-PROC names the `FD_CLOEXEC` clear before the exec, and
  FuguTTX HRN-WIRELOG names an inherited log descriptor. The child must close
  every other descriptor from 3 upward, so no unnamed descriptor leaks into a
  child. The sweep reads the open descriptor list where the platform gives one.
  On OpenBSD the sweep is a bounded loop to `_SC_OPEN_MAX`, because a `/dev/fd`
  read needs the `rpath` promise.
- **LIB-PROCESS-4** — `spawn_peer` must start a peer child over a socketpair,
  with the child end on a named descriptor number. A privileged parent then runs
  unprivileged children in the OpenBSD daemon pattern. FuguTTX HRN-PROC names
  the pattern: one socketpair for each child, created before the fork.
- **LIB-PROCESS-5** — `find_command` must resolve a command to an executable
  path. A name that holds a solidus is a path, and the method must test that
  path alone. A plain name must walk `PATH`. An absent name must walk `PATH`
  over the default list of the caller, in the order of that list. A candidate
  resolves only as a plain file that is executable. The method must answer the
  path, or undef. It must run no process, and it must not die. A module that
  drives a command then holds no resolver of its own.

<a id="lib-proxy"></a>

## Fugu::Proxy

A caching HTTP proxy, with its cache and its metadata. An optional feature: the
module requires the HTTP stack lazily.

<a id="lib-repl"></a>

## Fugu::REPL

A line editor for an operator prompt.

<a id="lib-random"></a>

## Fugu::Random

Random bytes and random passwords, from `/dev/urandom`.

<a id="lib-ssh"></a>

## Fugu::SSH

Run a command on another machine over SSH. An optional feature: the module
requires `Net::SSH2` lazily.

- **LIB-SSH-1** — `read_file` must read a remote file under a fixed size bound.
- **LIB-SSH-2** — A `strict` option and a `known_hosts` option on `new` must
  verify the host key of the peer. The check must run on every connection, and
  before any authentication. The default is permissive: the module provisions a
  fresh guest, and such a guest holds a new key after each install.

<a id="lib-sandbox"></a>

## Fugu::Sandbox

pledge and unveil as a platform abstraction.

<a id="lib-signal"></a>

## Fugu::Signal

Signal handlers for graceful shutdown.

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
- **LIB-SIGNER-10** — One run of the command must end within `timeout` seconds,
  with a default of 30. The run must take an argument list and never a shell. A
  run that makes a temporary directory must remove it on every exit. It must
  first stop each helper process that the command started under it.

<a id="lib-signify"></a>

## Fugu::Signify

The module follows [Fugu::Signer](#lib-signer) over signify(1), and it holds the
key pair, the signature file and the SHA256 manifest. It reads a public key
file, a signature file and a manifest, and it writes the manifest form for a
producer and a checker. The parent holds the three verbs, and this unit holds
the two engines, the manifest methods and the file formats.

- **LIB-SIGNIFY-1** — The manifest writer must sort its keys, so two runs write
  one byte sequence. It must reject a key that a stricter reader cannot carry. A
  parenthesis ends the key in a reader that stops at the first one. Whitespace
  breaks a reader that splits a line on space.
- **LIB-SIGNIFY-2** — The module must verify with two engines, and the `engine`
  option must name the one to take. The engine must select the verifier alone.
  The `perl` engine must use [Fugu::Ed25519](#lib-ed25519), and it must be the
  default. The `signify` engine must run the command, and a caller that names a
  `command` must get that engine. `generate` and `sign` must run the command
  under both engines. Under the `perl` engine `is_available` must return 1 with
  no command, per LIB-SIGNER-1, because `verify` runs. `command` must answer the
  resolved path, or undef, under both engines, and `command_absent` must follow
  LIB-SIGNER-9. Both engines must answer the same on the same input, and both
  must write the same error shape.
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

<a id="lib-statefile"></a>

## Fugu::StateFile

A small JSON state file.

<a id="lib-testlog"></a>

## Fugu::TestLog

A quiet process default logger for a test file.

<a id="lib-timeout"></a>

## Fugu::Timeout

Run something under a time limit.

<a id="lib-x509"></a>

## Fugu::X509

An X.509 certificate as bytes, and a detached CMS signature over a file. The
module decodes PEM and DER, computes the SHA-256 fingerprint, and reads the
subject, the issuer and the validity from the certificate. It runs openssl(1)
for a signature, through `Fugu::Process`.

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
- **LIB-X509-5** — Each method must take bytes, and must reject a string with a
  code point above 255, as LIB-OPENPGP-6 holds for the OpenPGP reader.
- **LIB-X509-6** — The PEM decoder must take one `CERTIFICATE` block, and must
  reject a private key block and a second block. A key directory publishes what
  the decoder accepts.

<a id="lib-protocol"></a>

## Protocol::Imsg

The OpenBSD imsg(3) frame, as bytes: a codec with no socket in it. The wire
format is in [protocol/MDNS-Imsg.md](protocol/MDNS-Imsg.md), and the conformance
tier replays it byte for byte.
