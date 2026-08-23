# 006 — Fugu::Process and Fugu::Control, the parent-and-children pattern

## Status

Proposed. Defers: LIB-PROCESS, LIB-CONTROL. Both units are `done`, and this plan
extends them. The gate below holds every part of this plan.

The `group` option on `Fugu::Process->terminate` and the `new_session` option on
`Fugu::Process->run` are in the code, with FuguTTX `HRN-CANCEL` as their caller
of record. This plan holds the rest: the `inherit` list, the descriptor sweep,
`spawn_peer`, and every `Fugu::Control` change. No consumer can call that work
today.

`Fugu::Control` is outside the allow-list of D7, so no consumer can load it.
`HRN-SOCKET` and HRN-CONFIRM-6 therefore keep the control socket and the
`SO_PEERCRED` read in the harness.

The FuguTTX plan `plans/001-fugu-module-allowlist/plan.md` holds the adoption
map of the allow-list. Its module table gives `Fugu::Process` the tool units —
`HRN-TOOL-RO`, `HRN-TOOL-GATE` and `HRN-CANCEL` — and it names `run`,
`spawn_command`, `exit_code`, `is_alive`, `terminate` and `wait_exit`. It names
no peer child and no inherited descriptor. `HRN-PROC` keeps the fork and the
exec of its own program, so `spawn_peer` and `inherit` hold no caller of record.

The gate is a rule of this repository, not a preference. `CLAUDE.md` states it:

> Do not keep test-only API. Delete a sub or option that only tests use,
> together with its test.

Every method and every option of this plan would have a test as its only caller.
The work must therefore wait for a consumer that names it.

## Purpose

`Fugu::Process` gains the parent side of the OpenBSD daemon pattern. It gains an
`inherit` descriptor list and a `spawn_peer` method over socketpair(2).

`Fugu::Control` gains the server side of the same pattern. `listen` gains a
`mode` argument and a `group` argument. The server gains `peer`, which reports
the user id, the group id and the process id of the connected peer.

Together the two modules let a Perl daemon run as a privileged parent with
unprivileged children. They also name the operator behind each connection.

## Why Fugu holds this work

Each piece is one system call, or the exact order of two of them. These are
kernel facts:

- a socketpair before a fork
- a descriptor flag before an exec
- a credential read on a UNIX socket

None of them names a consumer, a role, a socket path or a group.

`Fugu::Process` already owns the fork and the exec. `_fork_exec` in
`lib/Fugu/Process.pm` does the fork, the redirect and the exec. `_exec_pipe`
builds the close-on-exec pipe that reports an exec failure exactly.
`spawn_command` already calls setsid(2) for a daemon child:

```perl
			setsid() or _fail( $exec_w, "setsid: $!" );
```

`Fugu::Control` already owns the listen socket and its mode. The umask guard
sits in `listen`, on lines 141 to 147 of `lib/Fugu/Control.pm`:

```perl
	my $old      = umask 0177;
	my $listener = IO::Socket::UNIX->new(
		Type   => SOCK_STREAM,
		Local  => $self->{path},
		Listen => 5,
	);
	umask $old;
```

The work therefore extends two modules that already hold the neighbouring calls.
It adds no new module.

No consumer can hold this work instead. `App::FuguVM` is an application, so a
sibling repository must not load its modules. The FuguPass parent and the
FuguOracle service are C programs, so no Perl library can serve them.

## Consumers and citations

| Repo       | Unit          | Rules                                                                                                      | Need                                                                                                                                                                                                                      |
| ---------- | ------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FuguTTX    | `HRN-PROC`    | none: the unit holds a table and prose, and it holds no numbered rule                                      | The parent creates each socketpair before the fork, execs its own program with a role flag, and clears `FD_CLOEXEC` on the child end. The harness holds that code, so `spawn_peer` and `inherit` hold no caller of record |
| FuguTTX    | `HRN-SOCKET`  | none: the unit holds prose only                                                                            | `Fugu::Control` is outside the allow-list of D7, so the harness builds its own socket. The socket carries owner `_ttx`, group `ttxop` and mode `0660`. The frontend reads `SO_PEERCRED` for each connection               |
| FuguTTX    | `HRN-CONFIRM` | HRN-CONFIRM-6                                                                                              | `Fugu::Control` is outside the allow-list of D7. A confirmation must come from the same peer user id that saw the dry run                                                                                                 |
| FuguTTX    | `HRN-WIRELOG` | none: the anchor sits on one list item of the session-transcript unit, and the item holds no numbered rule | The parent opens the wire log before the fork, and the model process inherits the descriptor. The harness holds that code, so `inherit` holds no caller of record                                                         |
| FuguTTX    | `HRN-REPL`    | HRN-REPL-2, HRN-REPL-8                                                                                     | `Fugu::REPL` must not load `Fugu::Control`. The client watches the control socket as a bare handle                                                                                                                        |
| FuguPass   | `CLI-SPLIT`   | CLI-SPLIT-1, CLI-SPLIT-6, CLI-SPLIT-7                                                                      | Not a consumer. The vault core is C (D-16), and FuguPass holds no control socket                                                                                                                                          |
| FuguPass   | `CLI-IFACE`   | CLI-IFACE-1, CLI-IFACE-2                                                                                   | Not a consumer. The C core spawns the interface with a request pipe and a reply pipe, not a socketpair                                                                                                                    |
| FuguOracle | `TEST-FUZZ`   | TEST-FUZZ-1, and the new TEST-FUZZ-3                                                                       | Not a consumer. The fuzzer names `spawn_command`, `run` and `terminate`, and no rule asks for the group form                                                                                                              |
| FuguVM     | —             | none: FuguVM holds no `spec/` unit, and the `.pod` sidecar is the contract                                 | Not a consumer. `App::FuguVM::Guest` starts qemu with `spawn_command`, and it needs no peer child                                                                                                                         |

TEST-FUZZ-3 is a new rule of this same workflow. `TEST-FUZZ` holds TEST-FUZZ-1
alone today, so TEST-FUZZ-2, TEST-FUZZ-3 and TEST-FUZZ-4 are the next free
numbers.

### What the allow-list reaches, exactly

D7 also reads: "The port dependencies are llama.cpp and p5-Fugu, and no other."
The p5-Fugu package therefore reaches the target, and the import rule decides
what the harness loads. The allow-list holds `Fugu::Process`, and it holds no
`Fugu::Control`.

Four FuguTTX units need this work, and each one is `open` in the FuguTTX
register. `HRN-PROC`, `HRN-SOCKET`, HRN-CONFIRM-6 and `HRN-WIRELOG` keep their
code in the harness. A later proposal that adds `Fugu::Control` to the
allow-list would reach `HRN-SOCKET` and HRN-CONFIRM-6.

### Why FuguPass cannot use this work

FuguPass D-16 reads: "The vault core and the helper programs are C in KNF for
OpenBSD -stable." The process that forks is therefore C. CLI-IFACE-1 states the
channel: "the core process spawns `fugupass-repl` as a child, with a request
pipe and a reply pipe". A pipe pair is not a socketpair, and a C parent cannot
call a Perl class method. CLI-SPLIT-6 forbids a network service other than the
oracle client, so FuguPass holds no control socket either.

### Why Fugu::REPL stays out of this

FuguTTX HRN-REPL-2 reads: "The module must load with base modules only, and it
must stand alone: it must not load an other Fugu module." `Fugu::REPL` therefore
must not load `Fugu::Control` or `Fugu::Control::Client`.

HRN-REPL-8 needs the editor to watch the control socket. The client therefore
passes a bare handle: `Fugu::REPL->new(watch => [$socket])`. Plan 001 defines
`watch` as "Extra read handles, as an array reference", so a bare handle already
fits.

This plan adds no handle accessor to `Fugu::Control::Client`. The allow-list of
D7 holds no `Fugu::Control::Client`, so the FuguTTX client builds its own
socket. An accessor would have no caller of record, and `t/scripts/symbols.t`
would fail on it.

## Scope

In scope:

- One new argument on `spawn_command` and on `spawn_peer`, `inherit`.
- The descriptor sweep that `inherit` implies.
- One new method, `Fugu::Process->spawn_peer`.
- Two new arguments on `Fugu::Control->listen`, `mode` and `group`.
- Two new methods, `Fugu::Control->peer` and `Fugu::Control->peer_supported`.

Out of scope:

- Descriptor passing. FuguTTX HRN-PROC states the reason: "The core `Socket`
  module wraps neither `sendmsg(2)` nor `recvmsg(2)`, so `SCM_RIGHTS` is not
  expressible in base Perl." No pledge set holds `sendfd` or `recvfd` either.
- A supervisor. A parent that restarts a dead child holds policy: which child,
  how often, and after what delay. The caller owns that.
- A role vocabulary. The caller builds the command list, so the caller names its
  own flag.
- A `SOCK_SEQPACKET` or `SOCK_DGRAM` socketpair. `Fugu::Imsg` reassembles a
  frame from a stream, and no consumer asks for a datagram peer.
- An `inherit` argument on `run`. `run` owns the three standard descriptors and
  its own three pipes, so a caller has nothing to add.
- An `owner` argument on `listen`. A daemon binds the socket after the privilege
  drop, so the socket carries the daemon user already.
- A reader for the Linux `struct ucred`. See the field-order constraint below.
- A credential method on `Fugu::Control::Client`. A client learns nothing from
  its own credentials.
- Any transport in `Fugu::Process`. The method returns a plain handle, and the
  caller wraps it. `Fugu::Process` must not load `Fugu::Imsg`.
- A privilege drop or a pledge in the child. `Fugu::Privdrop` and
  `Fugu::Sandbox` own those, and the child calls them after the exec.

## Constraints that shape the design

### Perl closes an inherited descriptor at exec

FuguTTX HRN-PROC states the rule:

> Perl sets close-on-exec on each descriptor above `$^F`, so the parent must
> clear `FD_CLOEXEC` on the child end before `exec`, or move the descriptor
> below file descriptor 3.

`$^F` is 2 by default. A descriptor that Perl opened above 2 therefore does not
survive the exec. A caller that wants a child to inherit a log descriptor must
clear the flag. The `inherit` list is that clearing step, named once.

### The sweep must keep the exec-failure pipe

`_fork_exec` reports an exec failure over a close-on-exec pipe. The comment in
`lib/Fugu/Process.pm` states the mechanism:

```perl
		# The pipe is close-on-exec, so a successful exec closes
		# it and the parent reads EOF.
```

A sweep that closed that pipe would make the parent read an end of file. The
parent would then report success for a failed exec. The sweep must therefore
keep these descriptors:

- the standard three descriptors
- the descriptors of `inherit`
- the peer descriptor of `spawn_peer`
- the write end of the exec-failure pipe

### The sweep must not touch the file system

The child runs the sweep between the fork and the exec, so it holds the pledge
of the parent. A read of `/dev/fd` needs the `rpath` promise, and Fugu must not
demand one. `POSIX::sysconf(POSIX::_SC_OPEN_MAX())` needs no promise, and core
POSIX exports both names. The sweep therefore closes every descriptor in the
range, and it ignores each `EBADF`.

OpenBSD has closefrom(3), which does the same work in one call. Core Perl wraps
neither closefrom(3) nor close_range(2), so the loop is the only portable form.

### The socket must never widen before the group is right

The comment on `listen`, lines 124 to 127 of `lib/Fugu/Control.pm`, states the
rule that this plan must keep:

```perl
#	The socket is mode 0600 from birth, through a umask guard. A
#	chmod after the bind leaves a window in which any user on the
#	machine can connect. The directory that holds the socket is
#	the outer boundary, and the caller owns its mode.
```

`mode` fits the guard exactly. The method sets `umask 0777 & ~$mode` instead of
the fixed `umask 0177`, and it calls no chmod at all.

`group` cannot fit the guard, because bind(2) takes no group argument. The
method therefore binds under `umask 0177`, chowns the path to the group, and
then chmods to `$mode`. The order narrows first and widens last. At every
instant the set of users that can connect is a subset of the final set.

A non-root process can chgrp a file that it owns to a group that it belongs to.
A daemon therefore drops privilege with `Fugu::Privdrop->drop_privileges` first,
and calls `listen` after. The socket then carries the daemon user and the
operator group, and the method needs no root.

### The command handler signature must not change

A handler takes one argument today. `t/fugu/control.t` registers one on line 68:

```perl
			$control->register( ping => sub ($) { { pong => 1 } } );
```

`_serve_one` calls it on line 249 of `lib/Fugu/Control.pm`:

```perl
	my $reply = eval { $handler->( $request->{args} // {} ) };
```

A Perl signature dies on a surplus argument. The interpreter reports "Too many
arguments for subroutine", and it names the two counts. A second argument would
therefore break every registered handler in every consumer. The credentials must
reach a handler by an other route, so `peer` is a method on the server.

### The credentials belong to the connection, not to the request

`accept_one` takes one connection on line 168 and keeps it on line 171:

```perl
	my $client = $self->{listener}->accept or return;
	...
	$self->{clients}{ fileno $client } = $imsg;
```

The peer of an open connection cannot change. One getsockopt(2) per connection
is therefore enough, and `accept_one` is the place for it. `_serve_one` names
the current connection while a handler runs, and `peer` reports it.

### The field order is an OpenBSD field order

FuguTTX HRN-SOCKET states it: "On OpenBSD this option returns a
`struct sockpeercred`, which holds the user id, then the group id, then the
process id. Base Perl reads it with `getsockopt` and `unpack`, so no compiled
module is necessary. The field order differs from the Linux `struct ucred`, so
do not copy a Linux example."

The Linux `struct ucred` holds the process id first. A reader that assumes the
Linux order on OpenBSD returns the uid as the pid. That defeats HRN-CONFIRM-6,
because the gate then compares the wrong number.

One module must not carry two field orders. `peer` therefore reads the
credentials on OpenBSD only, and it reports "not supported" everywhere else.
`Fugu::Sandbox` sets the precedent on line 37 of `lib/Fugu/Sandbox.pm`:

```perl
use constant SUPPORTED => $^O eq 'openbsd';
```

The comment of that module names the reason for the companion predicate:

> A caller or a test uses is_supported, not a log line, to tell enforcement from
> emulation.

`peer_supported` serves the same purpose here.

## The interface contract

### Fugu::Process->spawn_command, the inherit argument

| Argument  | Meaning                                                            |
| --------- | ------------------------------------------------------------------ |
| `inherit` | An array reference of open handles. The default is the empty list. |

The child clears `FD_CLOEXEC` on each named descriptor. It then closes every
descriptor from 3 upward. It keeps a named descriptor, a standard descriptor,
and the exec-failure pipe.

The method keeps each named descriptor at its own number. A caller that must
tell a child a number reads `fileno` before the call, and puts the number in
`cmd`.

The clearing step runs after the redirect and before the chdir. The method
clears the flag with `fcntl($fh, F_SETFD, 0)`, because `FD_CLOEXEC` is the only
defined descriptor flag.

The sweep runs on every call, and it needs no argument. Perl already closes each
descriptor above `$^F` at the exec, so a caller that names nothing sees no
change. The sweep closes exactly the descriptors that a library left
inheritable, or that a caller cleared itself.

`inherit` dies when it is not an array reference, and when a member has no
descriptor. Both are programming errors.

### Fugu::Process->spawn_peer

`spawn_peer(%args)` starts a peer child over a socketpair.

| Argument  | Meaning                                                                        |
| --------- | ------------------------------------------------------------------------------ |
| `cmd`     | An array reference: the command and its arguments. This argument is necessary. |
| `fd`      | The descriptor number that the child receives. The default is 3.               |
| `inherit` | An array reference of extra handles, as above.                                 |

The method returns `{ success => 1, pid => $pid, socket => $handle }`. It
returns `{ success => 0, error => $message }` on any failure.

The method does this, in this order:

1. It creates the pair with `socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC)` from
   core `Socket`.
2. It forks over `_fork_exec`, so an exec failure comes back exactly.
3. In the child it closes the parent end, and dup2s the child end onto `fd`.
4. It clears `FD_CLOEXEC` on `fd`. A dup2 onto the same number is a no-op, and
   the flag then stays set, so the clearing step is unconditional.
5. It clears the flag on each `inherit` descriptor. It then sweeps every other
   descriptor from 3 upward, and it keeps `fd` and the exec-failure pipe.
6. It execs `cmd`.
7. In the parent it closes the child end, and returns the parent end.

The child opens its end with `open my $peer, '+<&=', $fd`, and the default
number is 3. The caller wraps the parent end when it wants framing:
`Fugu::Imsg->new(fh => $handle)`. `Fugu::Process` must not wrap it, because the
module holds no transport.

The caller names its own program and its own role flag. A FuguTTX parent passes
`[ $ttxd, '--role', 'model' ]`. The method must not default `cmd` to `$0`,
because a program can rewrite `$0`, and a relative `$0` breaks after a chdir.

The method dies when `fd` is below 3, and when `fd` collides with an `inherit`
descriptor. Both are programming errors.

The method makes no session and no process group. A peer child stays in the
group of the parent, so one signal can reach the whole set.

### Fugu::Control->listen, the mode and group arguments

| Argument | Meaning                                                                         |
| -------- | ------------------------------------------------------------------------------- |
| `mode`   | The socket mode, as an integer. The default is `0600`.                          |
| `group`  | The socket group, as a name or as a numeric group id. The default is undefined. |

With no `group` the method binds under `umask 0777 & ~$mode`, and it calls no
chmod. With the default mode the umask is `0177`, so an existing caller sees no
change.

With a `group` the method binds under `umask 0177`, chowns the path to the
group, and chmods the path to `$mode`.

A group name resolves with `getgrnam`. An unresolvable name, a failed chown and
a failed chmod are each a recoverable failure. The method then unlinks the
socket, sets `error`, and returns undef. A half-built socket must never accept a
connection.

`mode` dies when it is not an integer from 0 to `0777`. That is a programming
error.

`loop` keeps its meaning, and it stays necessary.

### Fugu::Control->peer

`peer()` returns the credentials of the connection that the server is answering
now, as a hash reference:

| Key   | Meaning                    |
| ----- | -------------------------- |
| `uid` | The user id of the peer    |
| `gid` | The group id of the peer   |
| `pid` | The process id of the peer |

The method returns undef outside a handler call, and undef when the platform is
not OpenBSD. A handler that needs the operator identity calls it, and a handler
that does not need it ignores it.

`accept_one` reads the credentials once, with `getsockopt` on `SOL_SOCKET` and
`SO_PEERCRED`. It unpacks three 32-bit fields, in the order uid, gid, pid. It
must check the length of the returned string before it unpacks.

A credential read that fails on OpenBSD closes the connection at once, and the
server logs the reason at error level. The read cannot fail on a healthy UNIX
socket, so a failure names a broken assumption. A control socket that cannot
name its peer must not answer.

The method holds no policy. It reports three numbers. The group of the socket is
the coarse gate, and the handler is the fine gate.

### Fugu::Control->peer_supported

`peer_supported()` is a class method. It returns true only where the platform
reports peer credentials in the `struct sockpeercred` order. A test uses it to
tell "not supported" from "the read failed".

## Load contract

The work needs core Perl only. It adds no line to the `cpanfile`, and no line to
a `deps/` manifest.

`Fugu::Process` imports `Fcntl`, `POSIX` and `Socket`. `Fcntl` already gives
`F_SETFD` and `FD_CLOEXEC` on line 22. `POSIX` already gives `setsid` and
`WNOHANG` on line 25, and it adds `sysconf`, `_SC_OPEN_MAX`, `dup2` and `close`.
`Socket` is new to the module, and it gives `AF_UNIX`, `SOCK_STREAM` and
`PF_UNSPEC`.

`Fugu::Control` already imports `Socket` on line 24, for `SOCK_STREAM`. It adds
`SOL_SOCKET` and `SO_PEERCRED`. The module must not hard-code the option number.
When core `Socket` does not define `SO_PEERCRED`, `peer` returns undef and sets
the reason.

`t/fugu/coreperl.t` proves the load contract, and `t/protocol/boundary.t` proves
that no `App::` namespace enters. `Fugu::Process` must not load `Fugu::Imsg`.

The work cites no `spec/` section of this repository, so `make spec-coverage`
sees no change.

## Files

| File                   | Content                                                                                           |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| `lib/Fugu/Process.pm`  | `inherit`, the sweep, and `spawn_peer`                                                            |
| `lib/Fugu/Process.pod` | The same additions. The DESCRIPTION says "Two methods start a child" today, and it must say three |
| `lib/Fugu/Control.pm`  | `mode`, `group`, `peer`, `peer_supported`                                                         |
| `lib/Fugu/Control.pod` | The same four additions, and the field order                                                      |
| `t/fugu/process.t`     | The new cases                                                                                     |
| `t/fugu/control.t`     | The new cases                                                                                     |

The module comment of `lib/Fugu/Process.pm`, lines 30 to 33, names two calls
that start a child. It must name three.

The work adds no module, so `lib/Fugu.pod` needs no index entry. It adds no
dependency, so the `cpanfile` and the three `deps/` manifests need no line.

## Tests

Both test files use `Test::More` with `done_testing()`. Each new case runs on
Linux and on OpenBSD, except the two cases that name a platform.

`t/fugu/process.t` proves:

- `spawn_peer` returns a handle and a pid. The parent writes bytes, the child
  echoes them on `fd` 3, and the parent reads them back.
- The child of `spawn_peer` needs no descriptor argument. The number is part of
  the contract, so the child opens `$fd` with `'+<&='`.
- `spawn_peer` reports an exec failure with the reason, for a command that does
  not exist.
- `spawn_peer` dies on an `fd` below 3, and on an `fd` that collides with an
  `inherit` descriptor.
- A descriptor in `inherit` reaches the child. The child appends to an open
  file, and the parent reads the file after the exit.
- A descriptor that is not in `inherit` does not reach the child. The test
  clears `FD_CLOEXEC` on a pipe write end, spawns a child, and proves the write
  fails.
- `inherit` dies on a value that is not an array reference.
- `spawn_command` keeps its result shape, its `daemonize` behavior and its three
  redirects.

`t/fugu/control.t` proves:

- `listen` with no `mode` gives mode `0600`, as it does today.
- `listen` with `mode => 0660` gives mode `0660`. The test sets a wide umask
  first, and the assertion still holds.
- `listen` with `group` set to the effective group id of the test gives that
  group on the socket.
- `listen` with an unresolvable group name returns undef, sets a reason in
  `error`, and leaves no file at the path.
- `listen` dies on a mode above `0777`.
- A registered handler with the signature `sub ($)` still answers, and one with
  `sub ($args)` still reads its arguments.
- `peer_supported` returns false off OpenBSD, and `peer` then returns undef.
- On OpenBSD, `peer` reports the uid of the test process, its gid, and the pid
  of the client. The subtest skips gracefully on an other platform.
- A call to `peer` outside a handler returns undef.

## Acceptance

- `make check` passes: `make lint`, `make test`, `make tidy` and
  `make spec-coverage`.
- `t/fugu/process.t` and `t/fugu/control.t` pass on Linux and on OpenBSD.
- `t/fugu/coreperl.t` passes: both modules load with core Perl only.
- `t/scripts/symbols.t` passes: each new sub has a caller in `lib/` or in a
  test.
- The two `.pod` sidecars document every new argument and every new method. The
  `Fugu::Control` sidecar states the `struct sockpeercred` field order, and it
  states that `peer` reports "not supported" off OpenBSD.
- The defaults must not change. `listen` gives mode `0600`. The
  `App::FuguVM::Guest` calls to `spawn_command`, `run` and `terminate` keep
  their exact meaning.
- Every new sub and every new option waits for a consumer that names it, because
  `lib/CLAUDE.md` forbids test-only API.

## Open questions

1. **`SO_PEERCRED` in the base perl of OpenBSD.** Core `Socket` exports the
   constant on Linux. The plan assumes the same on OpenBSD, and it falls back to
   an undef return with a reason. Confirm the export on an OpenBSD guest. If the
   constant is absent, the module needs a named constant for the OpenBSD value,
   and the sidecar must say so.
2. **The upper bound of the sweep.** `sysconf(_SC_OPEN_MAX)` reports 20000 on
   the development machine, and a container can report far more. The loop runs
   between the fork and the exec, once per spawn. Measure the cost. A lower
   bound is not correct, and core Perl wraps no closefrom(3), so a slow answer
   needs a new decision.
3. **The cancel of an in-flight generation.** The FuguTTX register notes that
   the abort mechanism needs a design. The group form of `terminate` covers a
   running tool, as HRN-CANCEL asks. It does not cover a blocked read of the
   model process, and this plan adds nothing for that.
4. **A second peer form.** A parent that starts several children of one role
   needs one socketpair for each. `spawn_peer` serves one child per call, and no
   consumer asks for a batch form today.
