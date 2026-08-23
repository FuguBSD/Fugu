# 005 — Fugu::Log, the syslog_method option

## Status

Proposed. The plan waits for its caller of record: the FuguTTX `HRN-SAFE-AUDIT`
harness call that names the transport. The plan cites no unit under an
Implements line while it waits. The register holds the `Fugu::Log` unit as done,
and the option is not a rule of the specification today. The change that lands
this plan adds the option rule to the unit, sets the register in the same
change, and deletes this plan directory.

`Fugu::Log` pins the syslog transport today: `new` and `reopen` each call
`setlogsock('native')` before `openlog`, and the module takes no option. This
plan adds the `syslog_method` argument on `Fugu::Log->new`, and the
`syslog_method` accessor.

The gate is a rule of this repository, not a preference. `lib/CLAUDE.md` states
it:

> Do not keep test-only API. Delete a sub or an option that only tests use,
> together with its test.

The option and the accessor have one reachable consumer. FuguTTX
`HRN-SAFE-AUDIT` names the transport that the harness needs: "The module pins
the native log method (`setlogsock('native')`), so the process needs no `unix`
promise." The allow-list of FuguTTX decision D7 holds `Fugu::Log`, so the
harness loads the module. The harness can name the method in the call, and the
accessor reports it, so the argument and the accessor hold a caller outside the
test tree. The plan must therefore land with that harness call. A test alone
must not be its caller.

The other named consumers name no transport:

- FuguPass CLI-SPLIT-9 keeps `fugupass-repl` in stderr mode or in quiet mode.
- `App::FuguVM::CLI` builds a stderr logger or a quiet logger.
- FuguOracle is C, so no Fugu module serves the service.

## Purpose

`Fugu::Log->new` takes the syslog transport as an option, with the default
`native`. The default serves the pledged OpenBSD daemon. The `native` mechanism
reports success in every case, and the C library drops a message that it cannot
deliver. A host with no working native transport therefore needs an other
transport, and the option is the answer for such a host. The accessor reports
the choice, so a harness can audit it.

## Consumers and citations

| Repo    | Unit             | Rules                                                     | Need                                                                                                       |
| ------- | ---------------- | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| FuguTTX | `HRN-SAFE-AUDIT` | none: the unit holds prose, and it holds no numbered rule | The allow-list of D7 holds `Fugu::Log`, so the harness loads the module. The unit names the native method. |

D7 holds the allow-list of the harness. The decision reads: "The Fugu module
allow-list holds `Fugu::REPL`, `Fugu::Sandbox`, `Fugu::Log`, `Fugu::Process`,
`Fugu::Config`, `Fugu::File` and `Fugu::CLI`." A CI check enforces that list.
FuguTTX plan `plans/001-fugu-module-allowlist/plan.md` holds the adoption map of
the allow-list, and it names the syslog pin as a prerequisite of
`HRN-SAFE-AUDIT`.

## Scope

In scope:

- One new option on `Fugu::Log->new`, `syslog_method`, with the default
  `native`.
- The name list as the `setlogsock` argument, in `new` and in `reopen`.
- One new accessor, `Fugu::Log->syslog_method`.
- One new rule under the `Fugu::Log` unit of `spec/library.md`, for the option.

Out of scope:

- A delivery check. No consumer needs one today.
- A change to the stderr mode or the quiet mode. Neither mode opens a socket.
- A remote log transport, a log format, and a rate limit. Each one is policy.

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

## Load contract

The change needs core Perl only. `Sys::Syslog` is a core module, and `Fugu::Log`
already imports `setlogsock` through the `:extended` tag. The change adds no
line to the `cpanfile` and no line to a `deps/` manifest.

## Files

| File               | Content                                                        |
| ------------------ | -------------------------------------------------------------- |
| `lib/Fugu/Log.pm`  | The `syslog_method` argument, its validation, and the accessor |
| `lib/Fugu/Log.pod` | The `syslog_method` item under `new`, and the accessor section |
| `t/fugu/log.t`     | The new subtests                                               |
| `spec/library.md`  | The option rule under the `Fugu::Log` unit                     |
| `spec/STATUS.md`   | The state of the `Fugu::Log` unit, in the same change          |

## Tests

The syslog tests replace the imported subs inside the `Fugu::Log` package, as
`t/fugu/log.t` does today, so no test opens a live syslog connection.

The tests prove:

- `syslog_method => ['native', 'unix']` reaches `setlogsock` as an array
  reference with both names, in that order.
- `syslog_method => []` calls `setlogsock` never, and still calls `openlog`.
- `new` dies for `syslog_method => 'nonsense'`, and the message matches
  `Invalid syslog method`.
- `new` dies for a name inside an array reference that the set does not hold.
- `syslog_method` returns an array reference with `native` for a default logger.
- `syslog_method` returns an empty array reference after `syslog_method => []`.
- A quiet logger accepts `syslog_method` and stores it. The mode decides the
  use, not the store.

## Acceptance

- `make check` passes.
- `t/fugu/log.t` passes, with every existing subtest and every new subtest.
- `t/scripts/symbols.t` passes: `syslog_method` has a caller of record.
- `lib/Fugu/Log.pod` documents `syslog_method`.
- No test opens a syslog connection. A run with no syslogd(8) on the host
  passes.

## Open questions

1. **The option name.** `syslog_method` follows the words of `Sys::Syslog`,
   which calls the value a "socket type (or mechanism)". It also follows the
   words of FuguTTX HRN-SAFE-AUDIT, which calls it "the native log method".
   `transport` and `mechanism` both read well too. The name is cheap to change
   before the first release that carries it.
2. **The risk of a pin with no delivery check.** The `native` mechanism reports
   success in every case. A host with no working native transport loses every
   log line, and the module cannot detect the loss. The option is the answer for
   such a host, and the default serves the OpenBSD daemon. No consumer needs a
   delivery check today.
