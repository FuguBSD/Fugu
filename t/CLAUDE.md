# t/

Applies when working on files under `t/`.

## Test tiers

| Tier        | Location             | Verifies                                    | Runs via    |
| ----------- | -------------------- | ------------------------------------------- | ----------- |
| Conformance | `t/conformance/`     | spec requirements, wire formats             | `make test` |
| Module      | `t/fugu/`            | Perl API behavior, error paths              | `make test` |
| Module      | `t/protocol/`        | the `Protocol::` codec, dependency boundary | `make test` |
| Tooling     | `t/scripts/` `t/ci/` | what `scripts/` and `.github/` produce      | `make test` |

Module tests follow the unit-test rules in `lib/CLAUDE.md` (skip gracefully on
missing dependencies) and need no citations.

Tooling tests are named after what they cover, such as `t/scripts/deps.t` for
`scripts/deps`. They drive the script as a subprocess, and they load no module.
They assert on exit status and output. `t/scripts/conventions.t` covers the
directory as a whole: exec bits, shebangs, and that every Perl script compiles.
`t/scripts/symbols.t` holds the API surface at its size. Every sub in
`lib/Fugu/` has a caller in lib/ or in a test. Every module has its one
documentation home, and every non-core import is in the `cpanfile`.

`t/ci/` is the exception to driving anything, because nothing under `.github/`
runs outside a runner. These tests read the workflows and the composite actions
as text, and they assert the invariants that only fail in CI. Every consumer of
an action must pass it a value that the action accepts. A cache key must hash
every input which decides what it caches.

## Conformance tier

One `.t` per normative spec topic file, named after the lowercased stem
(`spec/protocol/MDNS-Imsg.md` ↔ `t/conformance/mdns-imsg.t`). Rules:

- Every subtest name starts with a citation; catalog tables are data-driven
  loops citing `/<row>`; wire examples from the spec are replayed byte-exactly.
- Host-side, `Test::More` + `subtest`, `skip_all` on missing CPAN dependencies.
- Data tables and vectors live inline — no network, no external checkouts.
- The index file (`MDNS.md`) gets no test file; its few normative facts are
  covered by topic files.

## Spec citations

Any assertion of behavior from the protocol references in `spec/` must carry a
machine-parseable citation. The citation is a prefix of the subtest name or the
assertion description:

```
[<spec-stem> §<section>] <free text>
[<spec-stem> §<section>/<row>] <free text>      # unnumbered table rows
```

- `<spec-stem>` is the base file name of the protocol reference, without `.md`,
  e.g. `MDNS-Imsg` for `spec/protocol/MDNS-Imsg.md`.
- `<section>` is a numbered `##`/`###` heading anchor, e.g. `2.6` or `8`.
- The `/<row>` form points into an unnumbered table row.

One test may carry several citations. A citation asserts the section's
requirement — do not cite a section the test merely mentions.

`make spec-coverage` (`scripts/spec-coverage`) computes coverage of `spec/` and
stale-citation detection.
