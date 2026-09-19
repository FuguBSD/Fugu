# 015 — The devel/p5-Fugu port

## Status

Proposed. It waits on nothing. FuguPass PROG-PORT and FuguTTX HRN-PKG wait on
it, because both name the package as a run dependency.

Implements: REL-PORT.

## Purpose

The port packages the Fugu distribution from CPAN for OpenBSD, so a consumer
port can name `p5-Fugu` as a run dependency. Two sibling projects do.

## Constraints that shape the design

**The port is a CPAN port.** The Makefile sets `MODULES = cpan`,
`DISTNAME = Fugu-<version>`, `CATEGORIES = devel perl5`, and
`PERMIT_PACKAGE = Yes`. The license is ISC, and `COMMENT` comes from the
`dist.abstract` key of `.toolingrc`.

**No run dependency.** The library loads with core Perl only, per ARC-COREPERL,
so the port declares no run dependency. A `TEST_DEPENDS` line names each tool
that a test drives and that is outside the base system, or the test skips
without it.

**The pin follows the release.** `DISTNAME` and `distinfo` name the latest
release at implementation time. A later release updates them in a follow-up
change.

**Both architectures build.** The developer builds the port in an amd64 guest
and in an arm64 guest through `fuguvm`, as a command only.

**The tarball runs every staged test directory.** The `make test` of the tarball
must run `t/fugu`, `t/protocol`, and `t/conformance`. `scripts/dist` writes one
glob for each `dist.testdir` key of `.toolingrc` into the `TESTS` value of
`Makefile.PL`: `t/fugu/*.t t/protocol/*.t t/conformance/*.t`. The staging walk
is recursive, and each glob covers one level. Each of the three directories
holds its tests at the first level, so the globs cover every staged test. No
step of this plan changes `scripts/dist`.

## Files

| File                            | Change                                                |
| ------------------------------- | ----------------------------------------------------- |
| `ports/devel/p5-Fugu/Makefile`  | New. The port variables of the constraints above.     |
| `ports/devel/p5-Fugu/distinfo`  | New. The size and the checksum of the pinned tarball. |
| `ports/devel/p5-Fugu/pkg/DESCR` | New. The package description.                         |
| `ports/devel/p5-Fugu/pkg/PLIST` | New. The packing list.                                |
| `spec/STATUS.md`                | REL-PORT reads `done`.                                |

## Tests

- `make port-lib-depends-check`, `portcheck`, and `make test` of the port pass
  in both guests.
- A `pkg_add` of the built package then loads each `Fugu::` module with core
  perl.
- The guest test log names each skipped test and its missing tool.

## Acceptance

- `make check` passes on the host.
- The port builds on amd64 and on arm64.
- REL-PORT reads `done`.
- The change deletes this plan.

## Open questions

- Does `fuguvm` run an amd64 guest and an arm64 guest on the host of the
  developer? This repository holds no fact about the guests.

## What this plan does not do

It submits nothing to the ports tree, and it changes no module.
