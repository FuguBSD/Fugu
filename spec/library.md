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

<a id="lib-daemon"></a>

## Fugu::Daemon

Daemonization for Perl programs.

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

<a id="lib-log"></a>

## Fugu::Log

Logging to syslog, standard error, or nowhere.

- **LIB-LOG-1** — In syslog mode, the logger must give the `syslog_method`
  list to `setlogsock` before it opens the log, and a failed pin must die at
  the open. An empty list is the one exception: it pins nothing, and
  `Sys::Syslog` keeps its own order.
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
  must name the descriptors that a child keeps across the exec, each at its
  own number. FuguTTX HRN-PROC names the `FD_CLOEXEC` clear before the exec,
  and FuguTTX HRN-WIRELOG names an inherited log descriptor. The child must
  close every other descriptor from 3 upward, so no unnamed descriptor leaks
  into a child. The sweep reads the open descriptor list where the platform
  gives one. On OpenBSD the sweep is a bounded loop to `_SC_OPEN_MAX`, because
  a `/dev/fd` read needs the `rpath` promise.
- **LIB-PROCESS-4** — `spawn_peer` must start a peer child over a socketpair,
  with the child end on a named descriptor number, so a privileged parent runs
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
  verify the host key of the peer, on every connection and before any
  authentication. The default stays permissive: the module provisions a fresh
  guest, and such a guest holds a new key after each install.

<a id="lib-sandbox"></a>

## Fugu::Sandbox

pledge and unveil as a platform abstraction.

<a id="lib-signal"></a>

## Fugu::Signal

Signal handlers for graceful shutdown.

<a id="lib-signify"></a>

## Fugu::Signify

Verify a file against a small set of signify(1) public keys, and verify each
named file of a signed SHA256 manifest against its digest. The module holds no
private key and cannot sign.

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
