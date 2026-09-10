# 008 — The Perl floor: v5.34

## Status

Proposed. The implementation waits on one condition.

Extends: ARC-COREPERL. The implementation adds the floor rule to that unit and
lands the rule with the code.

The perl pack rule sheet `lib/CLAUDE.md` tells a writer to use `use v5.36` in
every file. That sheet is a synced copy, and this repository must not change it.
The implementation lands after the synced sheet names the floor of the
repository.

## Purpose

Fugu declares `use v5.36` in every module, every test, and one script. macOS
ships perl 5.34 in base, and Apple has frozen that version for years. A program
that packs Fugu into one file must run on a fresh macOS with the system perl.
FuguBench is that program. It carries a snapshot of the Fugu modules that it
uses, so the floor of Fugu is the floor of FuguBench.

This plan lowers the floor to v5.34. It changes no behavior. A grep over `lib/`
and `t/` finds no syntax that perl 5.34 cannot compile. The grep looked for a
`builtin::` call, a `try` block, a `defer` block, a multi-variable `foreach`,
and the `isa` operator. The change is the pragma block at the top of each file.

## Why Fugu holds this work

The floor is a property of the library, and the library declares it. A consumer
cannot lower the floor of a module that it packs. FuguBench DIST-PACK names the
snapshot, and FuguBench CLI-FUGU names the modules, so both depend on this plan.

## Consumers

| Repo      | Need                                                    |
| --------- | ------------------------------------------------------- |
| FuguBench | Pack Fugu into one file that the macOS system perl runs |
| FuguWeb   | Keep its own floor, or lower it in a plan of its own    |
| FuguVM    | Keep its own floor, or lower it in a plan of its own    |
| Tooling   | None. This plan waits on the perl pack rule sheet       |

## Scope

In scope:

- The pragma block of every module under `lib/`.
- The pragma block of every test under `t/`.
- The pragma block of `scripts/spec-coverage`, the one script that Fugu owns.
- A convention test that holds every Fugu-owned Perl file to the block.
- A skip in `t/scripts/dist.t` when the running perl is below 5.36. The test
  runs `scripts/dist` as a subprocess, and that script holds `use v5.36`.
- A CI leg that runs every Fugu-owned test on perl 5.34.
- The floor statement in `spec/index.md`, `README.md`, and `INSTALL.md`.
- Decision D-06, which this plan adds to `spec/DECISIONS.md`.
- The floor rule of ARC-COREPERL, which the implementation adds.

Out of scope:

- Every file that carries the org pack marker comment, such as `t/ci/local.t`
  and `t/ci/workflows.t`. An edit there breaks the drift gate, and the next sync
  restores `use v5.36`.
- `scripts/dist`. The perl pack of Tooling owns it, and it runs at build time on
  the CI perl. It never runs on a consumer host.
- The rule sheet `lib/CLAUDE.md`. Tooling owns it.
- The floor of FuguWeb and of FuguVM. Each repository decides its own.

## Constraints that shape the design

**The two feature bundles differ.** `use v5.36` turns on strict, warnings,
`say`, and `signatures`. It also turns off three features that let old code
compile: `indirect`, `multidimensional`, and `bareword_filehandles`. `use v5.34`
turns on strict and `say`, and it leaves the rest as it was. Four lines give the
same result on 5.34:

```perl
use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);
```

The `experimental` pragma turns on the `signatures` feature and silences its
warning. It is core since perl 5.20. The three feature names exist in perl 5.34,
so the `no feature` line compiles there. The synced `scripts/deps` uses the
first three lines already, for the same reason.

**The standard handles stay.** The `bareword_filehandles` feature governs a new
bareword handle only. `STDIN`, `STDOUT`, `STDERR`, and `ARGV` stay valid, as
they do under `use v5.36`.

**Perl::Critic wants both pragmas.** The `RequireUseWarnings` policy reads
`use v5.36` as a warnings pragma, and it reads `use v5.34` as none. The explicit
`use warnings` line satisfies it.

**The proof runs on the real floor.** A GitHub `macos-latest` runner ships
`/usr/bin/perl` 5.34, the perl that this plan targets. The leg runs the
Fugu-owned test tiers with that perl, and with no CPAN module:

```sh
make test TEST_GLOBS="t/fugu/*.t t/protocol/*.t t/conformance/*.t t/scripts/*.t"
```

A variable on the command line beats the assignment in `mk/local.mk`, so the leg
edits no file. The list holds no `t/ci/*.t`, because the two org pack tests hold
`use v5.36`. Perl 5.34 stops at that line before a skip can run, and the floor
covers the Fugu-owned files only. The leg must not run `make check`, because the
lint gate and the format gate need `Perl::Critic` and `Perl::Tidy` from CPAN. A
test that needs a CPAN module skips, as the test rules of `lib/CLAUDE.md`
demand. An `ubuntu-22.04` runner ships perl 5.34.0, and it is the fallback when
the macOS image moves on.

**The load contract stays.** ARC-COREPERL-1 holds: the change adds no module.
`t/fugu/coreperl.t` runs on the new leg, so the core-only proof runs on the
floor too.

## The change

Every Fugu-owned Perl file replaces its `use v5.36;` line with the four-line
block. The block sits where the one line sat, after the license header and
before the `package` line.

| File                         | Change                                                           |
| ---------------------------- | ---------------------------------------------------------------- |
| `lib/**/*.pm`                | The pragma block, in 28 files                                    |
| `t/**/*.t`                   | The pragma block, in 36 of the 38 files                          |
| `t/scripts/dist.t`           | A skip when the running perl is below 5.36                       |
| `scripts/spec-coverage`      | The pragma block                                                 |
| `t/scripts/conventions.t`    | Hold every Fugu-owned Perl file to the block                     |
| `.github/workflows/test.yml` | A `macos-latest` leg that runs the Fugu-owned tiers on perl 5.34 |
| `spec/index.md`              | The floor in the first paragraph                                 |
| `spec/architecture.md`       | The floor rule of ARC-COREPERL                                   |
| `spec/STATUS.md`             | The `ARC-COREPERL` note links the convention test                |
| `README.md`                  | The floor in the second paragraph                                |
| `INSTALL.md`                 | The floor in the first paragraph                                 |
| `spec/DECISIONS.md`          | Decision D-06, with this plan                                    |

The rule that the implementation adds reads: "Fugu must compile and run on perl
5.34, the perl that macOS ships in base. Every module, every test, and every
Fugu-owned script must start with the four-line pragma block."

## Tests

- `t/scripts/conventions.t` gains one check. Each `.pm` under `lib/`, each `.t`
  under `t/`, and `scripts/spec-coverage` must hold the four pragma lines. The
  lines must sit in order, before the first `package` line. A file with
  `use v5.36` fails the check. The check skips a file that carries the org pack
  marker comment, so `t/ci/local.t` and `t/ci/workflows.t` stay out.
- `t/scripts/dist.t` skips when the running perl is below 5.36. It runs
  `scripts/dist`, which holds `use v5.36`, so a lower perl cannot compile it.
- The macOS leg of `test.yml` runs the Fugu-owned tiers with `/usr/bin/perl`,
  through `TEST_GLOBS` on the command line. It installs nothing, so the leg
  proves the core-only claim and the floor claim in one run.
- `t/fugu/coreperl.t` stays as it is, and it runs on both legs.

## Acceptance

- `make check` passes on the Linux leg. The Fugu-owned tiers pass on the macOS
  leg, under `make test` with the named `TEST_GLOBS`.
- No Fugu-owned file under `lib/`, `t/`, or `scripts/spec-coverage` holds
  `use v5.36`.
- `spec/index.md`, `README.md`, and `INSTALL.md` name v5.34.
- ARC-COREPERL holds rule 3, and its register row stays `done` with a link to
  the convention test.
- The change deletes this plan.

## Open questions

None. The operator approved the floor change on 2026-09-10, with the decision to
build FuguBench in Perl on Fugu.
