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

- **LIB-LOG-1** — In syslog mode, the logger must pin the native format, so a
  pledged daemon logs the same bytes on every platform.

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
- **LIB-SSH-2** — The client must verify the host key of the peer.

<a id="lib-sandbox"></a>

## Fugu::Sandbox

pledge and unveil as a platform abstraction.

<a id="lib-signal"></a>

## Fugu::Signal

Signal handlers for graceful shutdown.

<a id="lib-signify"></a>

## Fugu::Signify

Verify a file against a signify(1) public key.

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
