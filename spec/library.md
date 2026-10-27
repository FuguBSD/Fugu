# The library

One module holds one concern. The library documents name each module and its
concern, and [index.md](index.md) lists them. The API contract of a module lives
in its `.pod` sidecar. A unit carries rules only where the design needs a
requirement beyond the sidecar.

This document holds the modules of a command-line tool: the command line, the
configuration, the log, and the prompt.

<a id="lib-cli"></a>

## Fugu::CLI

Subcommand dispatch for a command-line tool.

<a id="lib-config"></a>

## Fugu::Config

The OpenBSD-style configuration grammar.

- **LIB-CONFIG-1** — A value and a block argument must keep each byte of the
  file, and the module must not decode them. The parser must read ASCII white
  space alone as white space. A key and a block type must hold ASCII word
  characters alone.

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

<a id="lib-repl"></a>

## Fugu::REPL

A line editor for an operator prompt.

<a id="lib-testlog"></a>

## Fugu::TestLog

A quiet process default logger for a test file.
