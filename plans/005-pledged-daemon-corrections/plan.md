# 005 — Fugu::Log and Fugu::Privdrop, two corrections for a pledged daemon

## Status

Proposed.

## Purpose

`Fugu::Log` pins the syslog transport. In syslog mode the module calls
`setlogsock` before `openlog`, and the default method is `native`. A daemon that
pledges `stdio` then keeps its log. The method is an option, so a host with an
other transport can name it.

`Fugu::Privdrop->drop_privileges` verifies the real group id, the effective
group id, the real user id and the effective user id after the drop. The method
also reports a caller that was never root, in place of the silent success it
returns today.

Both modules ship today. Both are wrong for a pledged OpenBSD daemon. This plan
corrects them.

## Why Fugu holds this work

Both faults sit inside a shipped Fugu module, and no consumer can correct either
one from outside.

`Sys::Syslog` keeps the transport list in a lexical variable of its own package.
A caller cannot read it, and a caller cannot pass it to `openlog`. Only the code
that calls `openlog` can pin the list, and `Fugu::Log` is that code. The module
already owns the process-wide syslog state: the sidecar states that "a process
must create no more than one syslog-mode logger", because `openlog(3)` and
`closelog(3)` act on process-wide state.

A privilege drop is one sequence. `Fugu::Privdrop` calls setgid(2), sets the
group list, and calls setuid(2). A caller that verifies the result afterwards
verifies it too late: the module already returned 1 for a partial drop. The
verification belongs beside the calls.

Both changes stay inside the low-level Unix realm. Neither one names a consumer,
a facility, a user or a group.

## Consumers and citations

| Repo       | Unit             | Rules                                                              | Need                                                                                                                                                                                                                                                                 |
| ---------- | ---------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FuguTTX    | `HRN-SAFE-AUDIT` | none: the unit holds prose, and it holds no numbered rule          | **Blocked by D7.** The unit names the pin: "The harness pins the native log method (`setlogsock('native')`), so `Sys::Syslog` does not need the `unix` promise."                                                                                                     |
| FuguTTX    | `HRN-SAFE-DROP`  | none: the unit holds prose, and it holds no numbered rule          | **Blocked by D7.** The unit states: "It verifies each id after the drop." It also states: "A wrong order leaves a residual privilege."                                                                                                                               |
| FuguTTX    | `HRN-PROC`       | none: the unit holds a table and prose, and no numbered rule       | **Blocked by D7.** The parent pledge is `stdio rpath wpath cpath proc exec`. The set holds no `unix` promise, so a syslog transport that opens an AF_UNIX socket kills the parent. The model process pledges `stdio` alone.                                          |
| FuguOracle | `SEC-LOGGING`    | SEC-LOGGING-1                                                      | Not reachable: the service is C (D-07). The rule states the same fact for the C program: OpenBSD `syslog(3)` "delivers messages with the `sendsyslog(2)` system call: it needs no log socket, it works inside the chroot, and the `stdio` pledge promise covers it". |
| FuguPass   | `CLI-SPLIT`      | CLI-SPLIT-7, and the new CLI-SPLIT-9                               | `fugupass-repl` pledges `stdio tty`. CLI-SPLIT-9 keeps the program in stderr mode or in quiet mode, so the pin does not reach it.                                                                                                                                    |
| FuguVM     | —                | none: FuguVM holds no `spec/` unit, and the `.pod` is the contract | No change. `App::FuguVM::CLI` builds a stderr logger or a quiet logger, and no FuguVM module calls `drop_privileges`.                                                                                                                                                |

CLI-SPLIT-9 is a new rule of this same workflow. `CLI-SPLIT` holds CLI-SPLIT-1
to CLI-SPLIT-7 today, so CLI-SPLIT-8, CLI-SPLIT-9 and CLI-SPLIT-10 are the next
free numbers.

FuguTTX D7 blocks all three FuguTTX rows. The decision reads: "Perl for the
harness body, with base modules plus `Fugu::REPL`." It also reads: "the client
loads only this module from the distribution". A CI check enforces that list, so
the harness must not load `Fugu::Log` and must not load `Fugu::Privdrop`. The
harness therefore writes both mechanisms itself today. A change to that position
needs a change to D7 first, and a human must approve it. FuguTTX plan 001
carries that proposal.

The FuguTTX units are still the evidence for this plan. Two independent
specifications state the same two requirements, and both requirements belong to
the module that owns the mechanism.

## Scope

In scope:

- One new option on `Fugu::Log->new`, `syslog_method`, with the default
  `native`.
- The `setlogsock` call, before `openlog`, in `new` and in `reopen`.
- One new accessor, `Fugu::Log->syslog_method`.
- The id verification in `Fugu::Privdrop->drop_privileges`.
- The report of a caller that was never root, through the return value.
- The refusal of a mixed root state, and the refusal of user id 0 as a target.

Out of scope:

- A change to `prepare_statedir`. The method is correct, and no consumer asks
  for a change.
- A change to the stderr mode or the quiet mode of `Fugu::Log`. Neither mode
  opens a socket.
- A remote log transport, a log format, and a rate limit. Each one is policy.
- A `setgroups` wrapper. Perl exposes the call through `$)` alone, and the
  module needs no more.
- A public verification method for a caller that drops privilege itself. A
  caller that needs one is blocked by D7 today, so the method would have no
  caller of record.

## Constraints that shape the design

### What Fugu::Log does today

The module imports two tags on line 23 of `lib/Fugu/Log.pm`:

```perl
use Sys::Syslog qw(:standard :macros);
```

`setlogsock` is in neither tag. `Sys::Syslog` puts it in the `:extended` tag,
and that tag holds `setlogsock` alone. The import list therefore needs
`:extended`.

`new` opens the log on lines 131 to 134:

```perl
	if ( $mode eq MODE_SYSLOG ) {
		openlog( $ident, 'ndelay,pid', $self->{facility} );
		$self->{opened} = 1;
	}
```

`reopen` opens it again on lines 230 to 239:

```perl
sub reopen ($self)
{
	if ( $self->{mode} eq MODE_SYSLOG ) {
		closelog() if $self->{opened};
		openlog( $self->{ident}, 'ndelay,pid', $self->{facility} );
		$self->{opened} = 1;
	}

	return $self;
}
```

These are the two places that need the pin. Each one is the last statement
before the connection opens.

### What Sys::Syslog does

- The module keeps the transport list in `my @connectMethods`. The list is
  lexical to the `Sys::Syslog` package, so no caller can read it and no caller
  can pass a value into `openlog`.
- The documented default order is `native`, `tcp`, `udp`, `unix`, `pipe`,
  `stream`, `console`. On Linux and on FreeBSD the module drops `udp` from that
  order.
- `unix`, `stream` and `pipe` open a file-system object. `socket(2)` in the
  AF_UNIX domain needs the `unix` promise. `tcp` and `udp` need the `inet`
  promise. Only `native` stays inside `stdio`, because OpenBSD `syslog(3)`
  delivers with `sendsyslog(2)`.
- `setlogsock` sets the list. The documentation reads: "Sets the socket type and
  options to be used for the next call to `openlog()` or `syslog()`. Returns
  true on success, `undef` on failure."
- `openlog` connects at once when the options hold `ndelay`. `Fugu::Log` passes
  `'ndelay,pid'`, so the connection opens inside the `openlog` call. The pin
  must therefore come before `openlog`, in both places.
- `setlogsock` fails open. When no named mechanism passes its own check, the
  function restores the default list and returns a false value. A caller that
  ignores the return value then runs with `unix` in the list again.
- The list is process-wide. Any module in the same process can change it, and an
  operator can load such a module through `PERL5OPT`. One call at startup is
  therefore not enough: `reopen` must pin the list again.

### What Fugu::Privdrop checks today

`drop_privileges` starts on lines 130 and 131 of `lib/Fugu/Privdrop.pm`:

```perl
	# If the process is already non-root, there is nothing to do
	return 1 if $> != 0;
```

The guard reads the effective user id alone. Two faults follow. A caller that
never held root gets the same answer as a caller that dropped root, so the
caller cannot tell the two apart. And a process with real user id 0 and a
non-zero effective user id passes the guard, although seteuid(2) can bring root
back.

The drop itself runs on lines 136 to 154:

```perl
	unless ( POSIX::setgid($gid) ) {
		die "Cannot setgid to $gid: $!";
	}
	$( = $gid;    # Set the real GID
	...
	$) = $keep_groups ? "$gid" : "$gid $gid";

	# Drop the user privileges
	unless ( POSIX::setuid($uid) ) {
		die "Cannot setuid to $uid: $!";
	}
	$< = $uid;    # Set the real UID
	$> = $uid;    # Set the effective UID
```

`POSIX::setgid` and `POSIX::setuid` return the string `0 but true` on success
and `undef` on failure, so both `unless` guards are correct. The four
assignments report nothing. Perl performs the syscall and drops the result.

The module then checks the user ids on lines 156 to 167:

```perl
	# Make sure the process cannot get root back
	if ( $> == 0 || $< == 0 ) {
		die 'Failed to drop privileges - still running as root';
	}

	# Try to escalate. The attempt must fail. The check runs outside
	# an eval on purpose: an eval would swallow the die and report a
	# successful drop for a process that kept root.
	POSIX::setuid(0);
	if ( $> == 0 || $< == 0 ) {
		die 'Privilege drop failed - able to regain root';
	}
```

So the module checks the two user ids against 0, two times. It never checks them
against `$uid`. It never checks the group ids at all. A process that keeps group
id 0 passes every check today, and group 0 is the `wheel` group on OpenBSD.

### Constraints on the correction

- Perl offers no separate `setgroups`. `POSIX` does not hold the function. The
  one assignment to `$)` sets the effective group id and calls setgroups(2)
  together, and the module cannot split the two steps. The order that
  HRN-SAFE-DROP needs is therefore the order the module already has: setuid(2)
  comes last, so setgroups(2) still runs with root privilege.
- `$(` and `$)` can each hold a space-separated list. A numeric comparison on
  such a string warns under `use v5.36`. Each check must split the value first
  and compare the fields as numbers.
- The supplementary list is a set, not a sequence. getgroups(2) can report the
  effective group id inside the list. A check must therefore assert that every
  member of the list equals `$gid`, and must not assert a length.
- `keep_groups => 1` keeps a list that root gave the process. The module cannot
  know that list, so it must not verify it. The caller owns that risk. The
  sidecar already names the one case: the mdnsd(8) socket group.
- A test must not open a live syslog connection. No test in `t/` creates a
  syslog-mode logger today, and no module in `lib/` creates one. The new tests
  must keep that property.
- The verification must not use `eval`. A swallowed failure reports a successful
  drop for a process that kept root. The sidecar already states this rule.

## The interface contract

### syslog_method, on new

`new` takes one new argument.

| Argument        | Meaning                                                     |
| --------------- | ----------------------------------------------------------- |
| `syslog_method` | The syslog transport, as one name or as an array reference. |

The default is `native`.

The value is one mechanism name, or an array reference of names in the order to
try. An empty array reference means no pin: the module then calls `setlogsock`
never, and `Sys::Syslog` keeps its own order.

These are the names the module accepts: `console`, `inet`, `native`, `pipe`,
`stream`, `tcp`, `udp`, `unix`. They are the mechanism names of `Sys::Syslog`.
The `eventlog` mechanism is not in the set, because it needs the Win32 API, and
Fugu supports OpenBSD, Linux and Darwin.

`new` dies for any other name, with the message `Invalid syslog method: <name>`.
This matches the shape of the mode check, which dies with
`Invalid log mode: <mode>`. The module validates the value one time, at the
boundary, and never again.

`new` stores the value in every mode. It uses the value in syslog mode alone.
`ident` and `facility` behave the same way today.

### The pin, in new and in reopen

In syslog mode, and with a name list that is not empty, both methods call
`setlogsock` immediately before `openlog`. The call takes the list.

The methods die when `setlogsock` returns a false value, with the message
`Cannot pin the syslog method to <names>`. The module must not continue: the
function restored the default list, and that list holds `unix`. A daemon that
pledges `stdio` would then die at the first log line, with SIGABRT and no
diagnosis. A clear death at startup is the better outcome.

`reopen` pins the list again on every call. The list is process-wide state, so a
value that held at startup can be wrong later.

### syslog_method, the accessor

`syslog_method` returns an array reference. The reference holds the names in the
order the module gives to `setlogsock`. An empty reference reports that the
module pins nothing.

The accessor takes no argument. A caller must not change the transport of a
logger that is already open. `new` and `reopen` are the two places that talk to
`Sys::Syslog`, and both read the stored value.

### drop_privileges, the guard

The method reads both user ids and then acts on three cases.

| State                           | Action                        |
| ------------------------------- | ----------------------------- |
| `$<` is 0 and `$>` is 0         | Do the drop.                  |
| `$<` is not 0 and `$>` is not 0 | Change nothing, and return 0. |
| Exactly one id is 0             | Die.                          |

The third case is a mixed root state. A process in that state can call
seteuid(2) and get root back, and the module cannot guess which id the caller
wants. The message names both ids:
`Cannot drop privileges from a mixed root state: real <uid>, effective <uid>`.

The method resolves the user and the group after the guard, as it does today.
The method then dies when the resolved user id is 0, with
`Refusing to drop privileges to uid 0`. A drop to root is not a drop.

### drop_privileges, the verification

The method verifies the result after setuid(2), in one private helper,
`_verify_ids($uid, $gid, $keep_groups)`. The helper dies on the first failure.
It returns 1 otherwise.

These are the checks, in order:

| #   | Check                                                                      |
| --- | -------------------------------------------------------------------------- |
| 1   | The real group id, the first field of `$(`, equals `$gid`.                 |
| 2   | The effective group id, the first field of `$)`, equals `$gid`.            |
| 3   | With `keep_groups` 0, every field of the group list of `$)` equals `$gid`. |
| 4   | The real user id, `$<`, equals `$uid`.                                     |
| 5   | The effective user id, `$>`, equals `$uid`.                                |

Each message names the check, the value it found and the value it wanted, for
example `Privilege drop failed: real gid is 0, wanted 1000`.

The group checks come first. A wrong group id is the failure that the module
cannot see today, and the group calls run before the user calls.

The re-escalation probe stays. `drop_privileges` calls `POSIX::setuid(0)` after
the helper, and then calls the helper one more time. The second call proves that
the probe changed nothing. The probe and both calls stay outside an `eval`.

The checks replace the two `$> == 0 || $< == 0` tests. Check 4 and check 5 are
stronger: they compare against `$uid`, and `$uid` is never 0, because the method
already refused that target.

### drop_privileges, the return value

| Value | Meaning                                                           |
| ----- | ----------------------------------------------------------------- |
| 1     | The method dropped privilege, and every check passed.             |
| 0     | The process was already unprivileged. The method changed nothing. |

The method dies on every failure, as it does today. Both values are defined, so
a caller can tell a drop from a no-op, and neither value reports an error.

### The compatibility cost of the changed return value

The cost is real, and it is small today.

- The value 0 is false. A caller that writes
  `Fugu::Privdrop->drop_privileges(user => $u) or die` gets a new death, in one
  case only: the process was already unprivileged. A developer who runs a daemon
  in the foreground, as their own user, hits exactly that case.
- A caller that wants the old behaviour writes `defined ... or die`. The method
  never returns `undef`, so a `defined` test always passes. That form is a poor
  test, and this plan does not recommend it. A caller that must run as root
  should test for 1.
- A caller that ignores the return value sees no change.
- No module in `lib/` calls `drop_privileges`. The call sites of record are
  `t/fugu/privdrop.t` and the two examples in the sidecars, so the cost inside
  this repository is three files.
- `lib/Fugu/Privdrop.pod` states today: "A call from a process that is already
  unprivileged is a success." That sentence must go, and the table above must
  take its place.
- FuguVM calls the method never, so the release that carries this change needs
  no FuguVM change.

The change is worth the cost. A daemon that must run as `_myapp` and silently
runs as the operator is the failure this correction reports.

## Load contract

Both changes need core Perl only.

`Sys::Syslog` is a core module, and `Fugu::Log` already imports it on line 23.
The change adds the `:extended` tag to that same import. `POSIX` is a core
module, and `Fugu::Privdrop` already imports `setuid` and `setgid` from it. The
group calls go through `$(` and `$)`, which need no module.

The change adds no line to the `cpanfile` and no line to a `deps/` manifest.

`t/fugu/coreperl.t` proves the load contract. `t/scripts/symbols.t` checks that
every non-core import in `lib/` names a module of the `cpanfile`; both modules
are core, so the check needs nothing new. `t/protocol/boundary.t` proves that no
`App::` namespace enters `Fugu::`; the change adds no import, so the boundary
holds.

## Files

| File                                                                | Content                                                                                                                                   |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/Fugu/Log.pm`                                                   | The `:extended` import, the `syslog_method` argument and its validation, the `setlogsock` call in `new` and in `reopen`, and the accessor |
| `lib/Fugu/Log.pod`                                                  | The `syslog_method` item under `new`, the accessor section, the pledge fact, the risk of the pin, and one new bullet under ERRORS         |
| `lib/Fugu/Privdrop.pm`                                              | The new guard, the refusal of uid 0, `_verify_ids`, the second helper call after the probe, and the return value                          |
| `lib/Fugu/Privdrop.pod`                                             | The RETURN VALUES table, the new ERRORS bullets, the verification list under `drop_privileges`, and the `keep_groups` caveat              |
| `t/fugu/log.t`                                                      | The new subtests                                                                                                                          |
| `t/fugu/privdrop.t`                                                 | The new subtests, and the tighter test 5                                                                                                  |
| `lib/Fugu.pod`                                                      | No change. Line 44 and line 52 already hold the index entries, and neither summary changes                                                |
| `cpanfile`, `deps/OpenBSD.txt`, `deps/Linux.txt`, `deps/Darwin.txt` | No change. `Sys::Syslog` and `POSIX` are core modules                                                                                     |
| `README.md`                                                         | No change. Line 39 names `perldoc Fugu::Log` and holds no behaviour                                                                       |
| `spec/`                                                             | No change. The directory holds the mdnsd control references, and neither correction touches them                                          |

## Tests

Both test files use `Test::More` and `done_testing()` today. The new subtests
mirror the existing ones.

### t/fugu/log.t

No test may open a live syslog connection. The syslog tests therefore replace
the two imported subs inside the `Fugu::Log` package, and record the calls:

```perl
my @calls;
no warnings 'redefine';
local *Fugu::Log::setlogsock = sub { push @calls, [ 'setlogsock', @_ ]; 1 };
local *Fugu::Log::openlog    = sub { push @calls, [ 'openlog',    @_ ] };
```

The test replaces `*Fugu::Log::openlog` as well, so no test reaches
`openlog(3)`. It must replace the sub in the `Fugu::Log` package, not in
`Sys::Syslog`: the import copies the code reference, so a change in
`Sys::Syslog` alone reaches nothing.

The tests prove:

- A syslog logger calls `setlogsock` with `native`, and it calls it before
  `openlog`. The recorded order carries the proof.
- `reopen` on a syslog logger calls `setlogsock` again, and again before
  `openlog`.
- A stderr logger and a quiet logger call `setlogsock` never.
- `syslog_method => ['native', 'unix']` reaches `setlogsock` as an array
  reference with both names, in that order.
- `syslog_method => []` calls `setlogsock` never, and still calls `openlog`.
- A false return from `setlogsock` makes `new` die, and the message names the
  method list.
- A false return from `setlogsock` makes `reopen` die.
- `new` dies for `syslog_method => 'nonsense'`, and the message matches
  `Invalid syslog method`.
- `new` dies for a name inside an array reference that the set does not hold.
- `syslog_method` returns an array reference with `native` for a default logger.
- `syslog_method` returns an empty array reference after `syslog_method => []`.
- A quiet logger accepts `syslog_method` and stores it. The mode decides the
  use, not the store.

### t/fugu/privdrop.t

Test 5 becomes stricter. It runs as a non-root user, and it proves:

- `drop_privileges` returns 0 for a process that is already unprivileged.
- The return value is defined, so a caller can tell 0 from `undef`.
- The user id and the group id do not change.

Test 6 is a placeholder skip today. It becomes a real test, and it runs only as
root. The test forks, and the child does the whole drop, so the drop cannot
affect the rest of the suite. The parent reads the result over a pipe. The child
proves:

- `drop_privileges` returns 1.
- `$<` and `$>` both hold the user id of the target user.
- The first field of `$(` and the first field of `$)` both hold the group id of
  the target group.
- Every field of the group list of `$)` holds that same group id.
- A later `POSIX::setuid(0)` brings root back never.

Two further root tests prove the failure paths, each one in its own child:

- A drop with `group` set to a second group lands on that group, not on the
  primary group of the user.
- A drop with `keep_groups => 1` keeps the group list of root, and the two group
  id checks still pass.

The tests that need no root prove:

- `drop_privileges` dies for a user whose uid is 0. The test names the `root`
  user, and the message matches `Refusing to drop privileges to uid 0`. The test
  runs as root, because the guard returns 0 for a normal user before the
  resolve.
- `drop_privileges` dies for a mixed root state. Only root can build that state,
  so the test forks, and the child calls seteuid(2) before it calls the method.
  The message matches `mixed root state`. The test skips for a normal user, and
  a comment names the reason.

Every test that needs root skips with `plan skip_all` or with `skip`, as the
file does today. Every child test uses a fork, so no test changes the ids of the
test process.

## Acceptance

- `make check` passes: `make lint`, `make test`, `make tidy`, and
  `make spec-coverage`.
- `t/fugu/log.t` passes, with every existing subtest and every new subtest.
- `t/fugu/privdrop.t` passes as a normal user, and passes as root.
- `t/fugu/coreperl.t` passes: both modules load with core Perl only.
- `t/scripts/symbols.t` passes: `syslog_method` and `_verify_ids` each have a
  caller of record.
- `lib/Fugu/Log.pod` documents `syslog_method`, the pin, and the risk of the
  pin.
- `lib/Fugu/Privdrop.pod` documents the two return values, the verification
  list, and every new death.
- No test opens a syslog connection. A run with no syslogd(8) on the host
  passes.

## Open questions

1. **The risk of the pin.** The `native` mechanism reports success in every
   case. `Sys::Syslog` calls the C library, the C library drops a message it
   cannot deliver, and no error reaches the caller. A host with no working
   native transport therefore loses every log line, and the module cannot detect
   the loss. The option is the answer for such a host, and the default serves
   the OpenBSD daemon. No consumer needs a delivery check today.
2. **The option name.** `syslog_method` follows the words of `Sys::Syslog`,
   which calls the value a "socket type (or mechanism)", and the words of
   FuguTTX HRN-SAFE-AUDIT, which calls it "the native log method". `transport`
   and `mechanism` both read well too. The name is cheap to change before the
   first release that carries it.
3. **Group 0 as a target.** The plan refuses user id 0 and accepts group id 0.
   On OpenBSD group 0 is `wheel`, so a drop to group 0 keeps a privileged group.
   A refusal would be safer. No consumer asks for one, and a refusal could break
   a caller that this repository cannot see. The question needs one consumer
   before the answer changes.
4. **`keep_groups` and the group list.** With `keep_groups => 1` the module
   verifies the two group ids and skips the list. The retained list can hold
   group 0. The sidecar must state that the caller owns that risk. A safer form
   would take the extra groups by name, and set the list to exactly those
   groups. That form needs a consumer, and the mdnsd(8) case does not need it.
5. **FuguPass CLI-SPLIT-9 and syslog mode.** The new rule keeps `fugupass-repl`
   out of syslog mode, because "syslog mode opens a socket". With the pin,
   syslog mode opens no socket on OpenBSD: `sendsyslog(2)` sits inside `stdio`.
   The rule still holds, and this plan does not change it. A program that logs
   to the terminal has no need of syslog. The choice belongs to FuguPass, not to
   Fugu.
