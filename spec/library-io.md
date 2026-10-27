# The I/O modules

This document holds the modules that move data: the sockets, the files, the
event loop, and the network clients. The contract of each library unit is in
[library.md](library.md).

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

<a id="lib-mqtt"></a>

## Fugu::MQTT

A subscribing MQTT client for a single-threaded daemon. An optional feature: the
module requires `Net::MQTT::Simple` lazily.

<a id="lib-mdnsd"></a>

## Fugu::Mdnsd

Control mdnsd(8) over its control socket. The client implements publish only.
The wire protocol is in [protocol/MDNS-Control.md](protocol/MDNS-Control.md).

<a id="lib-proxy"></a>

## Fugu::Proxy

A caching HTTP proxy, with its cache and its metadata. An optional feature: the
module requires the HTTP stack lazily.

<a id="lib-ssh"></a>

## Fugu::SSH

Run a command on another machine over SSH. An optional feature: the module
requires `Net::SSH2` lazily.

- **LIB-SSH-1** — `read_file` must read a remote file under a fixed size bound.
- **LIB-SSH-2** — A `strict` option and a `known_hosts` option on `new` must
  verify the host key of the peer. The check must run on every connection, and
  before any authentication. The default is permissive: the module provisions a
  fresh guest, and such a guest holds a new key after each install.

<a id="lib-statefile"></a>

## Fugu::StateFile

A small JSON state file.

<a id="lib-protocol"></a>

## Protocol::Imsg

The OpenBSD imsg(3) frame, as bytes: a codec with no socket in it. The wire
format is in [protocol/MDNS-Imsg.md](protocol/MDNS-Imsg.md), and the conformance
tier replays it byte for byte.
