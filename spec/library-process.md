# The process modules

This document holds the modules that run a daemon and its child processes. The
contract of each library unit is in [library.md](library.md).

<a id="lib-daemon"></a>

## Fugu::Daemon

Daemonization for Perl programs.

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
- **LIB-PROCESS-6** — The reason of a failed execve(2) must start with
  `Cannot exec`, and each other start failure must start with another form.
  `spawn_command`, `spawn_peer`, `spawn_perl` and `run` share the step, so they
  share the form. The prefix is an interface: `Fugu::Signer` reads it to tell an
  absent command from a failure of the machinery, per LIB-SIGNER-9.

<a id="lib-sandbox"></a>

## Fugu::Sandbox

pledge and unveil as a platform abstraction.

<a id="lib-signal"></a>

## Fugu::Signal

Signal handlers for graceful shutdown.

<a id="lib-timeout"></a>

## Fugu::Timeout

Run something under a time limit.
