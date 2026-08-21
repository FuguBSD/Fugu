# 002 — Fugu::Process, an exact child environment

## Status

Proposed.

FuguTTX is a reachable consumer. The allow-list of FuguTTX decision D7 holds
`Fugu::Process`, so the harness loads the module. FuguTTX HRN-PERL names the
argument itself: "The fixed set comes from the `env` argument of
`Fugu::Process`. That argument must exist in the installed distribution, and the
minimum version of HRN-PKG covers it."

## Purpose

`Fugu::Process` gains one argument, `env`. The argument names the environment of
the child. The child then holds exactly the named variables. The parent
environment stays unchanged.

The module also loads `Config` at compile time. A caller that pledges without
the `rpath` promise can then call `spawn_perl` safely.

## Why Fugu holds this work

The environment of a child is a Unix process attribute. It sits beside the
working directory and the three standard descriptors. `Fugu::Process` already
owns the fork and the exec, and it already carries `cwd` for the same reason.
The module names no variable, so it holds no consumer policy.

No consumer can hold this work instead. `App::FuguVM` is an application, not a
library, so a sibling repository must not load its modules. A capability that a
consumer needs as a library must live in `Fugu::`.

Four consumers need an exact child environment today, and each one is a Perl
program that starts a foreign counterparty.

## Consumers and citations

| Repo       | Unit                   | Rules                                                                      | Need                                                                                                                                                                                   |
| ---------- | ---------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FuguOracle | `PROG-CGI`             | PROG-CGI-1, PROG-CGI-2                                                     | The CGI program dispatches on `REQUEST_METHOD` and `DOCUMENT_URI`, and it reads `CONTENT_LENGTH` bytes from standard input                                                             |
| FuguOracle | `TEST-FUZZ`            | TEST-FUZZ-1, and the new TEST-FUZZ-4                                       | The fuzzer calls the CGI program directly, so it must set the three CGI variables in the environment of each child                                                                     |
| FuguOracle | `TEST-ACCEPT`          | TEST-ACCEPT-1, and the new TEST-ACCEPT-3                                   | A byte-identical `200` body needs the same child environment on both sides                                                                                                             |
| FuguPass   | `QA-HARNESS`           | QA-HARNESS-2, QA-HARNESS-4, and the new QA-HARNESS-6                       | The harness starts each counterparty with `Fugu::Process`, and it gives each one its own record store                                                                                  |
| FuguPass   | `CLI-SPLIT`            | CLI-SPLIT-7                                                                | A program loads every module, and it then pledges `stdio tty`. A run-time `require` after that pledge aborts the process                                                               |
| FuguTTX    | `HRN-PERL`             | none: the unit holds bullets, and they hold no numbered rule               | The parent process runs each tool, and it holds the `exec` promise. HRN-PERL reads: "Reduce `%ENV` to a fixed safe set before any `exec`." The fixed set comes from the `env` argument |
| FuguVM     | `App::FuguVM::Console` | none: FuguVM holds no `spec/` unit, and the `.pod` sidecar is the contract | The expect child needs `FUGUVM_TIMEOUT` for one call only                                                                                                                              |

TEST-FUZZ-4, TEST-ACCEPT-3 and QA-HARNESS-6 are new rules of this same workflow.
`TEST-FUZZ` holds TEST-FUZZ-1 only today, and the same workflow appends
TEST-FUZZ-2, TEST-FUZZ-3 and TEST-FUZZ-4. `TEST-ACCEPT` holds TEST-ACCEPT-1 and
TEST-ACCEPT-2, so TEST-ACCEPT-3 is the next free number. `QA-HARNESS` holds
QA-HARNESS-1 to QA-HARNESS-5, so QA-HARNESS-6 is the next free number.

The FuguTTX row is reachable. D7 reads: "The Fugu module allow-list holds
`Fugu::REPL`, `Fugu::Sandbox`, `Fugu::Log`, `Fugu::Process`, `Fugu::Config`,
`Fugu::File` and `Fugu::CLI`." A CI check enforces that list, and
`Fugu::Process` is on it. FuguTTX plan `plans/001-fugu-module-allowlist/plan.md`
holds the adoption map of the list, and it names the `env` argument as a
prerequisite of HRN-PERL.

### Why a caller cannot do this itself

A caller can write `local $ENV{FOO} = 'bar'` before the call. That form has two
faults.

First, it changes the parent. The module already rejects the same shape for the
working directory. The comment on `run` states the rule:

```perl
#	The cwd option moves the child alone. A chdir in the parent
#	would change the meaning of every other relative path in the
#	program, and a second call that ran at the same time would race
#	it. A directory that the child cannot enter is a startup
#	failure with the reason, not a silent run in the wrong place.
```

Second, and decisively, `local` cannot give an exact environment. A caller that
wants exactly three variables must delete every other variable by name. The
caller does not know that list. A stray variable from the developer's shell then
enters the child, and the run stops being reproducible. FuguOracle TEST-ACCEPT-1
needs byte-identical bodies for identical input, so the child environment must
be exact.

FuguOracle D-06 sharpens the same point. The service must not read a
configuration file and must not read environment configuration. The CGI
environment must therefore hold the CGI variables and nothing else.

### The expect child of FuguVM today

`App::FuguVM::Console` runs each expect script with one call:

```perl
	my $result = Fugu::Process->run(
		cmd =>
		    [ 'expect', $script, $self->{host}, $self->{port}, @args ],
		passthrough => 1,
	);
```

The call passes no environment, so the child inherits the whole environment of
`fuguvm`. Each shipped script reads the timeout itself:

```tcl
proc env_timeout {default} {
    global env
    if {[info exists env(FUGUVM_TIMEOUT)] && $env(FUGUVM_TIMEOUT) > $default} {
        return $env(FUGUVM_TIMEOUT)
    }
    return $default
}
```

`install.exp` takes the value when it exceeds 300. `login.exp` takes it when it
exceeds 30. `command.exp` takes it in place of 60. FuguVM sets the variable
nowhere in `lib/`, `bin/` or `share/`. `man/fuguvm/fuguvm.1` documents no
environment variable. So the timeout reaches the child only when the operator
exports the variable in the shell.

The `env` argument replaces that path. `App::FuguVM::Console` can then name the
environment of the expect child, and it can put the timeout of this one call in
it. The value comes from the caller, and a configuration directive can supply
it. The shell of the operator stops deciding the timeout of an installation.

That change belongs in the FuguVM repository. This plan changes no FuguVM file.
The FuguVM plan must enumerate every variable that expect(1) needs, and `PATH`
is one of them. The next section states why.

## Scope

In scope:

- The `env` argument on `spawn_command` and on `run`.
- The same argument through `spawn_perl`, which passes its other arguments on.
- One validation of `env` at each public entry.
- The compile-time `Config` load, with every key that the module reads.
- The `.pod` text for both changes.

Out of scope:

- A merge mode. The argument replaces the environment. It does not add to it. A
  caller that wants a merge writes `{ %ENV, FOO => 1 }` in one expression.
- A delete list. A caller that names the whole environment needs no delete list.
- An implicit `PATH`. A silent addition would make "exactly the named variables"
  false, and it would break the reproducibility that TEST-ACCEPT-1 needs.
- A guard that refuses a secret-looking variable name. Fugu holds no consumer
  policy.
- `spawn_peer`, an `inherit` descriptor list, and a process-group `terminate`.
  Plan 006 holds that work.
- Any change to `exit_code`, `is_alive`, `terminate` or `wait_exit`.
- Any change to the FuguVM tree.

## Constraints that shape the design

- **No method dies.** The `.pod` states the contract: "No method dies. The
  methods report failures through the hash reference or the boolean value that
  they return." A bad `env` therefore returns an error, exactly as an empty
  `cmd` does today.
- **The parent must not change.** The child assigns `%ENV` after the fork. The
  parent `%ENV` keeps every key and every value.
- **Validate once, at the boundary.** `run` and `spawn_command` each reach
  `_fork_exec` directly, so each public method checks `env` once. `_fork_exec`
  must not check it again.
- **The child must assign the environment last.** The redirect opens files by
  path, and the chdir moves the child. Neither step reads the environment. The
  child therefore assigns `%ENV` after both steps and before the exec. The
  failure window stays as small as it can be.
- **execvp(3) searches `PATH`.** The child runs `exec { $cmd->[0] } @$cmd`, and
  Perl uses execvp(3). A cleared environment holds no `PATH`, so execvp(3) falls
  back to the default path of the system. A measurement proves the consequence:
  a program in a temporary directory is not found, and the error is "No such
  file or directory". A caller must give an absolute path, or must name `PATH`
  in `env`. The `.pod` must say so.
- **A pledged caller must not meet a run-time require.** FuguPass CLI-SPLIT-7
  shows the discipline: the program loads its modules, and it then pledges
  `stdio tty`. A `require` after the pledge needs `rpath`, and pledge(2) aborts
  the process instead.
- **`Config` hides a second file.** `Config.pm` holds a small key set, and every
  other key comes from `Config_heavy.pl`. A measurement gives the split on the
  perl of this checkout. `privlibexp`, `archlibexp`, `sitelibexp` and
  `sitearchexp` are light. `privlib`, `archlib`, `sitelib`, `sitearch`,
  `vendorlib`, `vendorarch`, `vendorlibexp` and `vendorarchexp` are heavy. The
  six keys that `_custom_inc_paths` reads are all heavy. A `use Config;` line
  alone is therefore not enough. A switch to the `*exp` keys does not help
  either, because the two vendor keys stay heavy. The split is an implementation
  detail of `Config.pm`, and a later perl can move a key. The design must not
  depend on it.
- **The module keeps no run-time state.** The header comment states it: "The
  module keeps no state and has only class methods." A compile-time constant
  table is not run-time state, so the contract holds.
- **Core Perl only.** `Config` is a core module.

## The interface contract

### env, on spawn_command and on run

`env => \%vars` names the environment of the child. The keys are the variable
names. The values are the variable values.

| Case                                     | Result                                                                                                |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| The caller omits `env`                   | The child inherits the environment of the parent. This is the behavior today, and it does not change. |
| The caller gives a hash reference        | The child holds exactly the named variables.                                                          |
| The caller gives an empty hash reference | The child holds an empty environment.                                                                 |

`exists $args{env}` separates the second case from the first. Thus `{}` and an
absent argument are not the same.

The parent `%ENV` does not change. The child assigns `%ENV` between the fork and
the exec.

The method validates `env` once, at the call. These are the errors:

- The value is not a hash reference.
- A name holds no character.
- A name holds an equals sign or a NUL byte.
- A value is not defined, or a value holds a NUL byte.

`spawn_command` reports an error as `{ success => 0, error => $msg }`. `run`
reports it through `_run_error`, so `success` is 0, `exit_code` is `EXIT_ERROR`,
`stdout` and `stderr` are empty, and `error` gives the reason. Neither method
forks in that case.

A caller must name every variable that the child needs. `PATH` is one of them
when the command is a bare name. `HOME`, `TERM`, `TZ` and `LC_ALL` can matter to
a given child, and the module adds none of them.

### env, on spawn_perl

`spawn_perl` deletes `code` and `args`, and it gives every other argument to
`spawn_command`. So `env` reaches the child with no new code.

The child still finds the modules of the parent. `spawn_perl` builds a `-I` flag
for each custom `@INC` path, and it puts the flags in the command list:

```perl
	$args{cmd} = [ $^X, @inc_flags, '-e', $code, @$extra_args ];
```

The paths travel in the argument list, not in `PERL5LIB`. A cleared environment
therefore costs the child no module. The `.pod` must state that fact, because a
caller can reasonably fear the opposite.

### _check_env

`_check_env($env)` is a new private function. It returns `undef` for a valid
argument. It returns the error message otherwise.

`spawn_command` and `run` each call it once, before any pipe and before the
fork. `_fork_exec` must not call it.

### _fork_exec

`_fork_exec($cmd, $cwd, $env, $redirect)` gains the third parameter. The
redirect callback stays last, so each call site keeps its shape.

The child gains one step. This is the child block today:

```perl
	if ( $pid == 0 ) {

		# Child process
		$DB::inhibit_exit = 0;
		close $exec_r;

		$redirect->($exec_w);
		_chdir_or_fail( $exec_w, $cwd );

		# The pipe is close-on-exec, so a successful exec closes
		# it and the parent reads EOF.
		exec { $cmd->[0] } @$cmd
		    or _fail( $exec_w, "Cannot exec $cmd->[0]: $!" );
	}
```

The child assigns `%ENV = %$env` after `_chdir_or_fail` and before the `exec`.
The assignment runs only when `$env` is defined. An undefined `$env` leaves the
inherited environment in place.

The exec failure path does not change. `_fail` writes to the close-on-exec pipe
and calls `POSIX::_exit`, and neither step reads the environment. So a caller
that forgets `PATH` still gets the exact reason, and it gets it at once.

### _run_passthrough

`_run_passthrough($class, $cmd, $timeout, $input, $cwd = undef, $env = undef)`
gains the sixth parameter. `run` passes `env` on with `cwd`, so a passthrough
run carries the same guarantee.

### The compile-time Config load

`_custom_inc_paths` holds one run-time require today:

```perl
sub _custom_inc_paths()
{
	require Config;
```

The module must load `Config` at compile time instead, and it must read every
key at compile time.

The module gains a `use Config;` line beside the other imports. It also gains
one `BEGIN` block. The block reads `privlib`, `archlib`, `sitelib`, `sitearch`,
`vendorlib` and `vendorarch`, and it stores the non-empty values in a file-scope
hash, `%DEFAULT_INC`. The read pulls `Config_heavy.pl` into memory at compile
time.

`_custom_inc_paths` then reads `%DEFAULT_INC` and touches `%Config` no more. The
function keeps its signature, its return value and its two skip rules: it skips
a reference, and it skips the current directory.

`Fugu::Sandbox` already carries `use Config;` at the top of the file, so the
compile-time load is the house style of this repository.

One caller rule follows, and the `.pod` must state it: a caller must load
`Fugu::Process` before it pledges. A lazy `require Fugu::Process` after a pledge
without `rpath` aborts the process, and no change inside this module can prevent
that.

## Load contract

The change needs core Perl only. `Config` is a core module, so the module adds
no line to the `cpanfile` and no line to a `deps/` manifest.

`t/fugu/coreperl.t` proves the load contract. It compiles every module against
an `@INC` that holds the core paths plus `lib/`, and `Config` sits in a core
path.

`t/scripts/symbols.t` checks that every non-core import in `lib/` names a module
of the `cpanfile`. `Config` is core, so the check needs nothing new.

`t/protocol/boundary.t` proves that no `App::` namespace enters `Fugu::`. This
change adds no import, so the boundary holds.

The module already imports `Fugu::CLI` for `EXIT_ERROR`. `Config` adds no new
dependency direction.

## Files

| File                                                                | Content                                                                                                                                        |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/Fugu/Process.pm`                                               | The `env` argument, `_check_env`, the new `_fork_exec` and `_run_passthrough` signatures, `use Config;`, the `BEGIN` block, and `%DEFAULT_INC` |
| `lib/Fugu/Process.pod`                                              | The `env` item under `spawn_command` and under `run`, the `PATH` caution, the `-I` fact under `spawn_perl`, and the pledge rule                |
| `t/fugu/process.t`                                                  | The new subtests                                                                                                                               |
| `lib/Fugu.pod`                                                      | No change. Line 54 already holds the index entry for the module                                                                                |
| `cpanfile`, `deps/OpenBSD.txt`, `deps/Linux.txt`, `deps/Darwin.txt` | No change. `Config` is a core module                                                                                                           |
| `README.md`                                                         | No change. The file holds no module table                                                                                                      |

## Tests

`t/fugu/process.t` gains the subtests below. Each one names the interpreter by
an absolute path, so no test depends on `PATH`. The file uses `Test::More` and
`done_testing()` today, and the new subtests mirror the existing ones.

The environment tests prove:

- `run` with `env` gives the child exactly the named variables. The child prints
  its sorted `%ENV`, and the test compares the whole list.
- `run` without `env` gives the child the environment of the parent. The test
  sets one marker variable and finds it in the child.
- `env => {}` gives the child an empty environment.
- The parent `%ENV` holds the same keys and the same values after each call.
- `run` with `passthrough => 1` and `env` reaches the child. The captured
  streams are empty in that mode, so the child exits 0 only when the variable
  matches, and the test reads `exit_code`.
- `spawn_command` with `env` reaches the child. The child writes its environment
  through the `stdout` argument, into a file in a temporary directory. The test
  reads the file after `wait_exit`.
- `spawn_perl` with `env` reaches the child, and the child still loads a module
  of the checkout. The environment holds no `PERL5LIB`, so the `-I` flags carry
  `@INC` alone.
- A bare command name fails when `env` holds no `PATH`. The test creates the
  program in a temporary directory, so the default path of execvp(3) does not
  find it. The error names the command.
- The same bare name succeeds when `env` holds that temporary directory in
  `PATH`.

The validation tests prove that each bad `env` returns an error and starts
nothing. The cases are a value that is not a hash reference, an empty name, and
a name with an equals sign. The other cases are a name with a NUL byte, an
undefined value, and a value with a NUL byte. One test asserts the `run` shape:
`success` is 0, `exit_code` is `EXIT_ERROR`, and both streams are empty.

The pledge test proves the compile-time load. A child compiles the module and
prints the state of `%INC` at once, with no method call:

- `$INC{'Config.pm'}` is set after `use Fugu::Process;`.
- `$INC{'Config_heavy.pl'}` is set after `use Fugu::Process;`.

The second assertion is the one that matters. It fails today, and it is the
exact proof that a pledged caller of `spawn_perl` reads no file.

## Acceptance

- `make check` passes: `make lint`, `make test`, `make tidy`, and
  `make spec-coverage`.
- `t/fugu/process.t` passes, with every existing subtest and every new subtest.
- `t/fugu/coreperl.t` passes: the module loads with core Perl only.
- `t/scripts/symbols.t` passes: `_check_env` has a caller in `lib/`.
- The `.pod` sidecar documents `env` on `spawn_command` and on `run`, with the
  `PATH` caution. It also documents the rule that a caller loads the module
  before it pledges.

## Open questions

1. **The passthrough signature.** `_run_passthrough` reaches six positional
   parameters with `env`. A hash reference of options would read better. The
   function is private, so a later change costs nothing outside the module. The
   plan keeps the positional form for now, because plan 006 touches the same
   path and can group the two changes.
2. **`Fugu::Sandbox->perl_lib_dirs`.** The method reads `privlibexp`,
   `archlibexp`, `sitelibexp` and `sitearchexp` at run time. All four are light
   on the perl of this checkout, so the call needs no `Config_heavy.pl` today. A
   later perl can move a key, and the call would then abort under a pledge
   without `rpath`. The same `BEGIN` treatment would remove the risk. No
   consumer reports the fault, so the plan leaves the module alone.
3. **A named-variable audit.** A child that inherits a parent variable can carry
   a secret into a process list. `env` gives a caller the tool to prevent that,
   and it enforces nothing. A check that warns on a common secret name would be
   consumer policy, and Fugu holds none. The question stays open for a consumer
   specification.
