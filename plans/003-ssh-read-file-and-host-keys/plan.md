# 003 — Fugu::SSH: read a remote file, and verify a host key

## Status

Proposed, in two parts. Part one can land now. Part two waits for a caller.

Part one is `read_file`. It holds `read_file`, the `MAX_READ_SIZE` constant, and
the `_read_all` helper.

Part two is the host-key policy. It holds the `known_hosts` argument and the
`strict` argument on `new`. It also holds the host-key check in `_connect`, the
strict argument list of `interactive`, and the `_ssh_argv` helper.

FuguVM plan 003 `guest-file-transfer` is the caller of record of part one. That
plan states the need: "Fugu plan 003 adds `Fugu::SSH->read_file`, beside the
`write_file` that stands today." Part one can therefore land now.

No caller sets the strict mode today. Open question 1 below states the same
fact. The gate is a rule of this repository, not a preference. `CLAUDE.md`
states it:

> Do not keep test-only API. Delete a sub or option that only tests use,
> together with its test.

A test would be the only caller of the `known_hosts` argument and the strict
mode. Part two must therefore wait. Two candidate callers can end the wait:

- A FuguVM directive that sets the strict mode. No FuguVM plan holds such a
  directive today. FuguVM plan 003 puts the policy out of scope: "A host key
  policy. Fugu plan 003 owns the `strict` and `known_hosts` options, and no verb
  of this plan sets either one."
- FuguTTX `IAC-TRAINCRED` (spec/infrastructure.md). The unit delivers a train
  credential to a cloud instance over SSH, so that copy needs a verified host
  key. The unit holds no numbered rule. FuguTTX decision D7 blocks the caller.
  D7 reads: "the client loads only this module from the distribution", and that
  module is `Fugu::REPL`. A human must approve a change to D7 first, and FuguTTX
  plan `plans/001-fugu-module-allowlist/plan.md` carries that proposal.

## Purpose

`Fugu::SSH` gains `read_file`. The method reads a remote file over SFTP and
returns its bytes. It reads the size first, and it reports a short read as a
failure.

The module also gains a host-key policy. A `known_hosts` argument names the file
to read. A `strict` argument turns verification on. In the strict mode every
method that connects verifies the key, and `interactive` verifies it too.

The default stays permissive. The module verifies nothing until a caller asks.

## Why Fugu holds this work

`Fugu::SSH` already holds one half of the transfer. `write_file` writes bytes
over SFTP, and no method reads them back. The module is the one home of the SFTP
code, so the read belongs beside the write.

The consumers reach a guest through `fuguvm`, a command. Hard rule 1 of the
briefing states that a sibling application is not a library, so FuguVM must not
grow a second SFTP client. A capability that a consumer needs as a library must
live in `Fugu::`. `fuguvm get` needs a remote read, so the read lands here.

The host-key decision hides inside the module today. `interactive` builds this
argument list:

```perl
	my @cmd = (
		'ssh',
		'-o',
		'StrictHostKeyChecking=no',
		'-o',
		'UserKnownHostsFile=/dev/null',
		'-o',
		'LogLevel=ERROR',
		'-p',
		$self->{port},
		"$self->{user}\@$self->{host}",
	);
```

A caller cannot see that choice, and a caller cannot change it. The `.pod`
records the limit in CAVEATS: "The module does not verify the host key." A
security decision must sit at the interface, where a caller reads it.

## Consumers and citations

| Repo       | Unit                               | Rules          | Need                                                                  |
| ---------- | ---------------------------------- | -------------- | --------------------------------------------------------------------- |
| FuguVM     | plan 003 `guest-file-transfer`     | —              | `fuguvm get` reads a guest file, and `fuguvm put` writes one          |
| FuguOracle | `TEST-INTEROP` (spec/testing.md)   | TEST-INTEROP-7 | The harness copies the test report out of the guest with `fuguvm get` |
| FuguOracle | `ARCH-DEPS` (spec/architecture.md) | ARCH-DEPS-5    | `fuguvm put` copies the source tree and the port files into the guest |
| FuguPass   | `QA-HARNESS` (spec/testing.md)     | QA-HARNESS-7   | The harness copies the build and the vectors in with `fuguvm put`     |
| FuguTTX    | `TRN-TRACES` (spec/training.md)    | — (prose only) | The rollout driver copies each transcript out of the guest            |

Three cited rules are new in this workflow. Each number is the next free number,
and each count comes from the file:

- FuguOracle `TEST-INTEROP` holds TEST-INTEROP-1 to TEST-INTEROP-3 today.
- FuguOracle `ARCH-DEPS` holds ARCH-DEPS-1 to ARCH-DEPS-4 today.
- FuguPass `QA-HARNESS` holds QA-HARNESS-1 to QA-HARNESS-5 today.

FuguTTX `TRN-TRACES` holds no numbered rule. The workflow changes its prose
only, so the row cites no rule.

Every consumer reaches this work through the `fuguvm` command. No consumer calls
`Fugu::SSH` itself.

FuguTTX must not call `Fugu::SSH`. Decision D7 states that "the client loads
only this module from the distribution", and that module is `Fugu::REPL`. A
direct use of `Fugu::SSH` in the FuguTTX harness is blocked. FuguTTX plan 001
proposes the change to D7, and it waits for a human.

No consumer rule asks for host-key verification today. Two facts still make the
options necessary:

1. The module hides the decision, as the argument list above shows. A caller
   cannot audit a choice that it cannot read.
2. `read_file` widens what the module carries. The method copies data out of a
   host. FuguTTX `IAC-CI` reaches a development host with a public address over
   SSH from a GitHub runner. A copy across that path needs verification, and the
   module must be able to give it.

## Scope

In scope:

- `read_file($remote_path, $max_size)`, and the `MAX_READ_SIZE` constant.
- A `known_hosts` argument and a `strict` argument on `new`.
- One host-key check in `_connect`, so every connecting method inherits it.
- The same policy in the ssh(1) argument list of `interactive`.
- Two private helpers, each with one caller: `_read_all` and `_ssh_argv`.
- The `.pod` sections for the new API, and a new CAVEATS text.

Out of scope:

- Trust on first use. FuguVM forwards one guest port for each project, and it
  reuses that port after a new install. A key that a first use recorded then
  rejects the next guest. A first-use record on a loopback port proves nothing.
- The module must not write a `known_hosts` file. The strict mode reads the
  file, and it must not add a key to it.
- A stream from the remote file to a local path. `read_file` returns bytes, and
  the caller writes them with `Fugu::File->write_atomic`. That order leaves no
  partial local file. A stream would leave one.
- A list form of `run_command`. The method keeps its string argument. FuguVM
  plan 003 owns the quoting of an argument list.
- A recursive copy of a directory. One call reads one file.
- A cipher choice and a key-exchange choice. libssh2 and ssh(1) keep their own
  defaults.

## Constraints that shape the design

**The default must stay permissive.** A guest that booted a moment ago holds a
new host key. `fuguvm up` installs the guest, and the guest generates its keys
at the first boot. FuguVM then reaches it on the loopback address:

```perl
	# The connection uses the SSH agent for authentication. Connect
	# over IPv4: QEMU forwards the guest SSH port on 127.0.0.1 only.
```

One address and one port therefore hold a different key after each install. A
strict default would fail every `fuguvm ssh` call, every `wait_available` poll,
and every key install of `App::FuguVM::Guest`. The default must verify nothing.

**The permissive mode must not call `check_hostkey`.** Net::SSH2 documents the
strict policy as its default: "Only host keys already present in the known hosts
file are accepted. This is the default policy." The default file is
`~/.ssh/known_hosts`. A call with no argument would break every caller that
lives today, so the permissive mode must skip the call.

**Verification must run before authentication.** `_connect` sends the password
when the agent fails. A password that reaches the wrong host is a lost password.
The check must sit between `connect` and `auth_agent`.

**One connect path serves every method.** The module already states the shape:

```perl
# $self->_with_connection($code):
#	Open the connection, run $code->($ssh2), disconnect, and
#	return what $code returned. The method returns undef when the
#	connect fails, so every remote operation shares one
#	connect-run-disconnect shape.
```

So one check in `_connect` covers `run_command`, `write_file`, `read_file`,
`is_available` and `wait_available`. `read_file` needs no connect code of its
own.

**`interactive` needs the policy again.** The method runs ssh(1), so it carries
the policy as command options and not as a library call. The strict mode must
reach it, because a caller must not lose verification when it opens a session.

**Net::SSH2 loads lazily, so an import is not available.** The code must name
the policy in full: `Net::SSH2::LIBSSH2_HOSTKEY_POLICY_STRICT()`.

**The method needs Net::SSH2 0.60 or later.** Release 0.59_05 renamed
`check_remote_hostkey` to `check_hostkey` and set the argument order to
`check_hostkey( [policy, [known_hosts_path [, comment] ] ] )`. Release 0.60 is
the first stable release with that order. In the strict mode the module must
test `Net::SSH2->can('check_hostkey')`, and it must die with a message that
names the version. The module must not pin a version in a manifest:
`deps/OpenBSD.txt` names the package `p5-Net-SSH2`, and a package line carries
no version.

**A short read is normal.** Net::SSH2::File documents `read ( buffer, size )` as
"Read size bytes from the file into a given buffer. Returns number of bytes
read, or undef on failure." A large file needs many reads. The read must loop,
and the loop must compare the total with the size that `stat` reported. The
module already applies the same rule to the write:

```perl
			# A short write leaves a truncated remote file. A
			# provisioning script that arrives half-written is
			# worse than one that never arrived, so the return
			# value is checked.
```

A file that arrives half-read is worse than one that never arrived, because the
caller cannot see the difference.

**A signature copies its arguments.** `read` writes into the caller's variable.
A stand-in reader in the test must therefore use `@_`, and it must not use a
signature.

**`Fcntl` already imports the flag.** Line 22 of the module reads:

```perl
use Fcntl     qw(O_RDONLY O_WRONLY O_CREAT O_TRUNC);
```

Nothing uses `O_RDONLY` today. `read_file` uses it, so the import stops being
dead.

## The interface contract

### new

`new` gains two arguments. The method still opens nothing and reads nothing. It
stores the two values.

| Argument      | Meaning                                                          |
| ------------- | ---------------------------------------------------------------- |
| `known_hosts` | The path of the known_hosts file to read. The default is absent. |
| `strict`      | Verify the host key of every connection. The default is 0.       |

`strict` carries the name of both back ends: it selects
`LIBSSH2_HOSTKEY_POLICY_STRICT` for the library, and `StrictHostKeyChecking=yes`
for ssh(1).

The policy belongs to the object. No method takes a per-call override, because
one object reaches one host.

With `strict` 0 the module verifies nothing, and `known_hosts` has no effect. A
path that only the strict mode reads must not change the permissive mode.

With `strict` 1 and no `known_hosts`, both back ends read `~/.ssh/known_hosts`.
That is the default of each back end, so the module invents no default of its
own.

### read_file

`read_file($remote_path, $max_size)` reads a remote file over SFTP. It returns
the bytes of the file. `$max_size` defaults to `MAX_READ_SIZE`.

The method works in this order:

1. It opens the SFTP session.
2. It reads the size with `stat($remote_path)`.
3. It refuses a size above `$max_size`, before it reads one byte.
4. It opens the file with `O_RDONLY`.
5. It reads with `_read_all`, and it compares the total with the size.

The method returns `undef` for every failure:

- A connect that fails.
- An SFTP session that fails.
- A `stat` that fails.
- A size above `$max_size`.
- An open that fails.
- A total that differs from the size.

An empty remote file returns the empty string. A caller must therefore test
`defined`, and a caller must not test truth. The `.pod` must state that rule,
because the empty string is false.

The method reports each reason with `Fugu::Log->default->debug`.
`Fugu::File->read` reports a failed open the same way. A developer thus reads
one kind of line for a local read and for a remote read.

The two halves report a result in two shapes, and the `.pod` must say so:

| Method       | Success           | Failure |
| ------------ | ----------------- | ------- |
| `write_file` | 0, like a command | 1       |
| `read_file`  | the bytes         | `undef` |

`read_file` returns data, so it follows `Fugu::File->read`. `write_file` returns
a status, so it follows a command. Both shapes are already in Fugu.

### MAX_READ_SIZE

`MAX_READ_SIZE` is 64 MiB, beside `DEFAULT_TIMEOUT` and `BUFFER_SIZE`.

`read_file` holds the whole file in memory, and the CAVEATS of the `.pod`
already report the same fact for `run_command`. A guest can hand back a disk
image, and a cap fails closed. A caller that needs more must name a larger
`$max_size`.

### The host-key check in `_connect`

In the strict mode `_connect` must run three steps in this order: connect,
verify, authenticate.

The verify step calls
`$ssh2->check_hostkey( Net::SSH2::LIBSSH2_HOSTKEY_POLICY_STRICT(), $path )`,
with `$path` from `known_hosts`. The method omits the second argument when the
caller gave no path.

A failed verification must die. The message must name the host, the port and the
file. It must also end with a newline. The operator then reads one line, and not
a stack trace.

A die is the correct answer for four reasons:

- A caller that asked for verification must not lose the answer to a missing
  return-value test.
- A wrong key is permanent. A retry cannot repair it.
- `wait_available` polls. A poll must not hide a wrong key for a whole timeout.
- `Fugu::Random` and `Fugu::Sandbox` set the precedent. A security failure in
  Fugu dies.

In the permissive mode `_connect` calls nothing new. The added code must sit
inside one `if`, so the existing path keeps its behavior exactly.

`check_hostkey` dies when it cannot learn the host name. That path cannot open
here, because `new` always holds `host` and `_connect` passes it to `connect`.

### interactive

`interactive` builds its argument list with `_ssh_argv`. The permissive list
stays exactly as it is today. The strict list differs in three options:

| Option                  | Permissive  | Strict                             |
| ----------------------- | ----------- | ---------------------------------- |
| `StrictHostKeyChecking` | `no`        | `yes`                              |
| `UserKnownHostsFile`    | `/dev/null` | the `known_hosts` value, or absent |
| `LogLevel`              | `ERROR`     | absent                             |

The permissive mode lowers the log level to hide the line that reports a new
key. The strict mode must show the host-key diagnosis, so the module must not
lower the level there.

`interactive` returns an exit code, and it must not die. ssh(1) refuses the
session itself and returns 255. So the module reports a wrong key in two shapes:
a library method dies, and `interactive` returns 255. The `.pod` must state both
shapes.

One difference between the back ends stays. ssh(1) also reads
`/etc/ssh/ssh_known_hosts`, and libssh2 reads the named file only. `interactive`
must not set `GlobalKnownHostsFile`, because an entry that an administrator
wrote is a local trust decision. The `.pod` must record the difference.

### The private helpers

`_read_all($file, $size)` reads `$size` bytes from `$file` and returns them. The
method loops, and it stops at `$size`. It returns `undef` when a read fails, and
it returns `undef` when the total differs from `$size`. A `$size` of 0 returns
the empty string.

`$file` needs one method only: `read($buffer, $length)`. So the test drives
`_read_all` with a small stand-in class, and it needs no server.

`_ssh_argv()` returns the ssh(1) argument list. `interactive` calls
`system( $self->_ssh_argv )`. The list always holds more than one element, so
perl runs no shell.

Both helpers are private, and each has one caller in `lib/`. The `.pod` must not
document them, because the `.pod` documents public API only.

## Load contract

`Net::SSH2` stays a lazy `require` inside `_connect`:

```perl
	eval { require Net::SSH2; 1 }
	    or die "Fugu::SSH needs Net::SSH2: $@";
```

`check_hostkey`, the policy constant and the `can` test all run after that
`require`. So the compile-time load of the module stays core Perl.

The module adds `use Fugu::Log`, which is core Perl and which `Fugu::File`
already uses.

The change adds no CPAN library. The `cpanfile` needs no line. No `deps/`
manifest needs a line: `deps/OpenBSD.txt` holds `test pkg p5-Net-SSH2`, and
`deps/Linux.txt` and `deps/Darwin.txt` hold `test cpan Net::SSH2`.

`t/fugu/coreperl.t` proves the load contract. `t/protocol/boundary.t` proves
that no `App::` namespace enters.

## Files

| File               | Content                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `lib/Fugu/SSH.pm`  | `read_file`, `_read_all`, `_ssh_argv`, `MAX_READ_SIZE`, the two `new` arguments, the `_connect` check, `use Fugu::Log` |
| `lib/Fugu/SSH.pod` | New sections for `read_file` and the two arguments; new text in RETURN VALUES, ERRORS and CAVEATS                      |
| `t/fugu/ssh.t`     | The new tests                                                                                                          |
| `lib/Fugu.pod`     | No change. The index entry exists, and its summary stays true                                                          |
| `README.md`        | No change. It names SSH in one line of prose, and the line stays true                                                  |
| `cpanfile`         | No change                                                                                                              |
| `deps/*.txt`       | No change                                                                                                              |

The CAVEATS of the `.pod` must change. It says today: "The module does not
verify the host key." The new text must name the default, must name the `strict`
argument, and must name the reason for the default. It must also report that
`read_file` holds the whole file in memory, beside the same fact for
`run_command`.

The ERRORS of the `.pod` says today: "No method dies for a connection that
fails." That sentence stays true, and the new text must add the one exception: a
host key that does not verify in the strict mode.

## Tests

`t/fugu/ssh.t` keeps its `plan skip_all` when `Net::SSH2` is absent. It uses
`Test::More` and `done_testing()`.

The test proves:

- `MAX_READ_SIZE` holds the documented value, beside the existing constant
  tests.
- `new` stores `known_hosts` and `strict`.
- `strict` defaults to 0, and `known_hosts` defaults to absent.
- `_read_all` returns the whole content when the reader gives it in pieces.
- `_read_all` returns the empty string for a size of 0.
- `_read_all` returns `undef` for a short read.
- `_read_all` returns `undef` when a read fails.
- `_read_all` stops at the size when the reader offers more bytes.
- `read_file` returns `undef` for a closed port, and it does not die.
- `_ssh_argv` in the default mode holds `StrictHostKeyChecking=no` and
  `UserKnownHostsFile=/dev/null`.
- `_ssh_argv` in the strict mode holds `StrictHostKeyChecking=yes`.
- `_ssh_argv` in the strict mode holds no `UserKnownHostsFile=/dev/null`, and it
  holds no `LogLevel=ERROR`.
- `_ssh_argv` in the strict mode with `known_hosts` holds
  `UserKnownHostsFile=<path>`.
- `_ssh_argv` holds the port and the `user@host` form.
- `_ssh_argv` returns more than one element, so perl runs no shell.

Two paths need a real server, and the unit test cannot build one:

- A successful `read_file`. FuguVM proves that path against a live guest, in the
  test of its plan 003.
- The die of the strict mode. The test proves the strict argument list instead,
  through `_ssh_argv`.

The plan states both limits, because a reader must not believe that the unit
test covers a successful transfer.

## Acceptance

- `make check` passes: `make lint`, `make test`, `make tidy`, and
  `make spec-coverage`.
- `t/fugu/ssh.t` passes, and it still skips when `Net::SSH2` is absent.
- `t/fugu/coreperl.t` passes: the module still loads with core Perl only.
- `t/scripts/symbols.t` passes: the test names `read_file`, and `interactive`
  and `read_file` name the two private helpers.
- The `.pod` documents `read_file`, both `new` arguments, both failure shapes,
  and the new CAVEATS text.
- FuguVM still passes against a build of this branch:
  `cpanm --local-lib=local ../Fugu/build/Fugu-*.tar.gz`, then `make check` in
  FuguVM. The permissive default must keep every existing FuguVM test green.

## Open questions

1. **No caller sets `strict` today.** The option closes the CAVEATS limit of the
   module, and it moves a security choice to the interface. A reviewer who wants
   no uncalled option has one alternative: keep the permissive options in one
   private constant, and add no strict mode. The plan chooses the option,
   because `read_file` copies data out of a host.
2. **Two shapes report one fault.** A library method dies, and `interactive`
   returns 255. One shape needs a `last_error` accessor, which adds state and
   public API. No consumer asks for it today.
3. **The size cap.** 64 MiB fits a test report, a transcript and a file listing.
   It does not fit a disk image. No consumer states a size today, so a later
   consumer can raise the argument instead of the constant.
