# Implementation register

This register is the one record of implementation state. One row exists for each
unit of the specification. A unit is one design element of one specification
document. The [conventions](index.md#conventions) define the unit IDs. Each row
describes the current state only. A row must not carry a plan name or a
reference to an earlier state. A note can carry the date of a recorded fact.

## States

| State   | Meaning                                                              |
| ------- | -------------------------------------------------------------------- |
| open    | No code implements the unit.                                         |
| partial | Code implements a part of the unit. The note names each absent part. |
| done    | Code implements the full unit. The note links the code or the tests. |
| n-a     | No code can implement the unit. It exists for citation only.         |

The "Done by" column names a phase of the [roadmap](ROADMAP.md), or "—" when no
phase applies.

## Units

| Unit                                             | State   | Done by | Note                                                                                                              |
| ------------------------------------------------ | ------- | ------- | ----------------------------------------------------------------------------------------------------------------- |
| [ARC-NAMESPACES](architecture.md#arc-namespaces) | done    | —       | [lib/Fugu](../lib/Fugu), [lib/Protocol](../lib/Protocol)                                                          |
| [ARC-BOUNDARY](architecture.md#arc-boundary)     | done    | —       | [boundary.t](../t/protocol/boundary.t)                                                                            |
| [ARC-COREPERL](architecture.md#arc-coreperl)     | done    | —       | [coreperl.t](../t/fugu/coreperl.t)                                                                                |
| [ARC-CALLERS](architecture.md#arc-callers)       | done    | —       | [symbols.t](../t/scripts/symbols.t)                                                                               |
| [ARC-GENERIC](architecture.md#arc-generic)       | n-a     | —       | Citation only.                                                                                                    |
| [LIB-CLI](library.md#lib-cli)                    | done    | —       | [CLI.pm](../lib/Fugu/CLI.pm), [cli.t](../t/fugu/cli.t)                                                            |
| [LIB-CONFIG](library.md#lib-config)              | done    | —       | [Config.pm](../lib/Fugu/Config.pm), [config.t](../t/fugu/config.t)                                                |
| [LIB-CONTROL](library.md#lib-control)            | done    | —       | [Control.pm](../lib/Fugu/Control.pm), [control.t](../t/fugu/control.t)                                            |
| [LIB-DAEMON](library.md#lib-daemon)              | done    | —       | [Daemon.pm](../lib/Fugu/Daemon.pm), [daemon.t](../t/fugu/daemon.t)                                                |
| [LIB-EVENTLOOP](library.md#lib-eventloop)        | done    | —       | [EventLoop.pm](../lib/Fugu/EventLoop.pm), [eventloop.t](../t/fugu/eventloop.t)                                    |
| [LIB-FILE](library.md#lib-file)                  | done    | —       | [File.pm](../lib/Fugu/File.pm), [file.t](../t/fugu/file.t)                                                        |
| [LIB-IMSG](library.md#lib-imsg)                  | done    | —       | [Imsg.pm](../lib/Fugu/Imsg.pm), [imsg.t](../t/fugu/imsg.t)                                                        |
| [LIB-JSONSOCKET](library.md#lib-jsonsocket)      | done    | —       | [JSONSocket.pm](../lib/Fugu/JSONSocket.pm), [jsonsocket.t](../t/fugu/jsonsocket.t)                                |
| [LIB-LOG](library.md#lib-log)                    | done    | —       | [Log.pm](../lib/Fugu/Log.pm), [log.t](../t/fugu/log.t)                                                            |
| [LIB-MQTT](library.md#lib-mqtt)                  | done    | —       | [MQTT.pm](../lib/Fugu/MQTT.pm), [mqtt.t](../t/fugu/mqtt.t)                                                        |
| [LIB-MDNSD](library.md#lib-mdnsd)                | done    | —       | [Mdnsd.pm](../lib/Fugu/Mdnsd.pm), [mdnsd.t](../t/fugu/mdnsd.t), [mdns-control.t](../t/conformance/mdns-control.t) |
| [LIB-PIDFILE](library.md#lib-pidfile)            | done    | —       | [Pidfile.pm](../lib/Fugu/Pidfile.pm), [pidfile.t](../t/fugu/pidfile.t)                                            |
| [LIB-PRIVDROP](library.md#lib-privdrop)          | done    | —       | [Privdrop.pm](../lib/Fugu/Privdrop.pm), [privdrop.t](../t/fugu/privdrop.t)                                        |
| [LIB-PROCESS](library.md#lib-process)            | done    | —       | [Process.pm](../lib/Fugu/Process.pm), [process.t](../t/fugu/process.t)                                            |
| [LIB-PROXY](library.md#lib-proxy)                | done    | —       | [Proxy.pm](../lib/Fugu/Proxy.pm), [proxy.t](../t/fugu/proxy.t)                                                    |
| [LIB-REPL](library.md#lib-repl)                  | done    | —       | [REPL.pm](../lib/Fugu/REPL.pm), [repl.t](../t/fugu/repl.t)                                                        |
| [LIB-RANDOM](library.md#lib-random)              | done    | —       | [Random.pm](../lib/Fugu/Random.pm), [random.t](../t/fugu/random.t)                                                |
| [LIB-SSH](library.md#lib-ssh)                    | partial | —       | The host-key verification of LIB-SSH-2 is absent. [SSH.pm](../lib/Fugu/SSH.pm), [ssh.t](../t/fugu/ssh.t)          |
| [LIB-SANDBOX](library.md#lib-sandbox)            | done    | —       | [Sandbox.pm](../lib/Fugu/Sandbox.pm), [sandbox.t](../t/fugu/sandbox.t)                                            |
| [LIB-SIGNAL](library.md#lib-signal)              | done    | —       | [Signal.pm](../lib/Fugu/Signal.pm), [signal.t](../t/fugu/signal.t)                                                |
| [LIB-SIGNIFY](library.md#lib-signify)            | done    | —       | [Signify.pm](../lib/Fugu/Signify.pm), [signify.t](../t/fugu/signify.t)                                            |
| [LIB-STATEFILE](library.md#lib-statefile)        | done    | —       | [StateFile.pm](../lib/Fugu/StateFile.pm), [statefile.t](../t/fugu/statefile.t)                                    |
| [LIB-TESTLOG](library.md#lib-testlog)            | done    | —       | [TestLog.pm](../lib/Fugu/TestLog.pm), [testlog.t](../t/fugu/testlog.t)                                            |
| [LIB-TIMEOUT](library.md#lib-timeout)            | done    | —       | [Timeout.pm](../lib/Fugu/Timeout.pm), [timeout.t](../t/fugu/timeout.t)                                            |
| [LIB-PROTOCOL](library.md#lib-protocol)          | done    | —       | [Imsg.pm](../lib/Protocol/Imsg.pm), [imsg.t](../t/protocol/imsg.t), [mdns-imsg.t](../t/conformance/mdns-imsg.t)   |
| [REL-VERSION](release.md#rel-version)            | done    | —       | [perl.mk](../mk/perl.mk), [dist](../scripts/dist)                                                                 |
| [REL-ASSETS](release.md#rel-assets)              | done    | —       | [release.yml](../.github/workflows/release.yml)                                                                   |
| [REL-BUILD](release.md#rel-build)                | done    | —       | [build.yml](../.github/workflows/build.yml)                                                                       |

## Update protocol

1. The change that implements a unit, or a part of a unit, sets the state of the
   unit in this register, in the same change.
2. A `partial` note names each absent rule or part.
3. A `done` note holds at least one relative link to code or to tests.

## Code roots

The drift gate maps each document to the code that implements it.

| Document        | Roots                                               |
| --------------- | --------------------------------------------------- |
| architecture.md | `lib`, `t`                                          |
| library.md      | `lib`, `t`                                          |
| release.md      | `GNUmakefile`, `mk`, `scripts`, `.github/workflows` |

## Retired IDs

| ID  |
| --- |
