# Decisions

This document holds the decisions that govern Fugu. A plan must not go against a
decision. To change a decision, propose the change and get human approval first.

| ID   | Decision                                                                                                             | Rationale                                                                                 |
| ---- | -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| D-01 | Fugu loads with core Perl only. Every CPAN use is a lazy `require` behind an optional feature.                       | A consumer installs nothing to load the library, and the optional features stay optional. |
| D-02 | The dependency direction is one way: `Protocol::` uses core Perl only, and `Fugu::` never uses `App::`.              | A codec stays testable as bytes, and an application never becomes a library.              |
| D-03 | No threads. A daemon multiplexes with `IO::Select`.                                                                  | One process with one loop stays debuggable, and OpenBSD daemons share the shape.          |
| D-04 | Fugu stays generic: no consumer policy lives in the library.                                                         | A generic module serves every sibling repository the same way.                            |
| D-05 | The tests are the callers of record. A sub with no caller in `lib/` or in a test is deleted, together with its test. | A library keeps no dead API surface.                                                      |
