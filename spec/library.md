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
- **LIB-ED25519-4** — The check must follow section 5.1.7 of RFC 8032. It must
  treat a scalar at or above the group order, and a point encoding that decodes
  to no point, as a signature that does not verify. Such an encoding is not
  canonical, and two encodings of one signature would let a signature count
  twice.
- **LIB-ED25519-5** — `verify` must return 1 for a signature that verifies, and
  0 for one that does not. A shape error is a failure: the method returns undef,
  and `error` holds the reason. A caller then tells bad input from a file that
  is not authentic.
- **LIB-ED25519-6** — The module must hold no private key operation. It must not
  sign, and it must not derive a key. A signature is a human act, and signify(1)
  makes it.
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
`security.txt`.

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

An armored OpenPGP public key as bytes. The module holds the armor decoder and
the version 4 fingerprint of a public key packet. It also holds the Web Key
Directory hash of an email local part. It runs no command, so a caller needs no
gpg(1). It reads a public key only, and it verifies no signature.

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

<a id="lib-signify"></a>

## Fugu::Signify

Verify a file against a small set of signify(1) public keys. Verify each file of
a signed SHA256 manifest against its digest. The module also reads and writes
the SHA256 manifest form, so a producer and a checker share one implementation.
A manifest key is the text between the parentheses, and the module holds it as
text. The key can be a file name, a file path, or a download URL. The caller
maps each key to a local path. The module holds no private key and cannot sign.

- **LIB-SIGNIFY-1** — The manifest writer must sort its keys, so two runs write
  one byte sequence. It must reject a key that a stricter reader cannot carry. A
  parenthesis ends the key in a reader that stops at the first one. Whitespace
  breaks a reader that splits a line on space.

<a id="lib-statefile"></a>

## Fugu::StateFile

A small JSON state file.

<a id="lib-testlog"></a>

## Fugu::TestLog

A quiet process default logger for a test file.

<a id="lib-timeout"></a>

## Fugu::Timeout

Run something under a time limit.

<a id="lib-protocol"></a>

## Protocol::Imsg

The OpenBSD imsg(3) frame, as bytes: a codec with no socket in it. The wire
format is in [protocol/MDNS-Imsg.md](protocol/MDNS-Imsg.md), and the conformance
tier replays it byte for byte.
