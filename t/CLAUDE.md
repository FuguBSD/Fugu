# t/

Applies when working on files under `t/`.

## Test tiers

| Tier        | Location             | Verifies                                    | Runs via    |
| ----------- | -------------------- | ------------------------------------------- | ----------- |
| Conformance | `t/conformance/`     | spec requirements, wire formats             | `make test` |
| Module      | `t/fugu/`            | Perl API behavior, error paths              | `make test` |
| Module      | `t/protocol/`        | the `Protocol::` codec, dependency boundary | `make test` |
| Tooling     | `t/scripts/` `t/ci/` | what `scripts/` and `.github/` produce      | `make test` |

Module tests follow the unit-test rules in the root `CLAUDE.md` (skip gracefully
on missing dependencies) and need no citations.

Tooling tests are named after what they cover — `t/scripts/deps.t` for
`scripts/deps` — and drive it as a subprocess rather than loading a module, so
they assert on exit status and output. `t/scripts/conventions.t` covers the
directory as a whole: exec bits, shebangs, and that every Perl script compiles.
`t/scripts/symbols.t` holds the API surface at its size: every sub in
`lib/Fugu/` has a caller in lib/ or in a test, every module has its one
documentation home, and every non-core import is in the `cpanfile`.

`t/ci/` is the exception to driving anything: nothing under `.github/` runs
outside a runner, so these tests read the workflows and the composite actions as
text and assert the invariants that only fail in CI — that every consumer of an
action passes it a value the action accepts, and that a cache key hashes every
input which decides what it caches.

## Conformance tier

One `.t` per normative spec topic file, named after the lowercased stem
(`spec/MDNS-Imsg.md` ↔ `t/conformance/mdns-imsg.t`). Rules:

- Every subtest name starts with a citation; catalog tables are data-driven
  loops citing `/<row>`; wire examples from the spec are replayed byte-exactly.
- Host-side, `Test::More` + `subtest`, `skip_all` on missing CPAN dependencies.
- Data tables and vectors live inline — no network, no external checkouts.
- The index file (`MDNS.md`) gets no test file; its few normative facts are
  covered by topic files.

## Spec citations

Any assertion of behavior defined by the protocol references in `spec/` must
carry a machine-parseable citation as a prefix of its subtest name or assertion
description:

```
[<spec-stem> §<section>] <free text>
[<spec-stem> §<section>/<row>] <free text>      # unnumbered table rows
```

- `<spec-stem>` is the spec file name without `spec/` and `.md`, e.g.
  `MDNS-Imsg` for `spec/MDNS-Imsg.md`.
- `<section>` is a numbered `##`/`###` heading anchor, e.g. `2.6` or `8`.
- The `/<row>` form points into an unnumbered table row.

One test may carry several citations. A citation asserts the section's
requirement — do not cite a section the test merely mentions.

Coverage of `spec/` and stale-citation detection are computed by
`make spec-coverage` (`scripts/spec-coverage`).
