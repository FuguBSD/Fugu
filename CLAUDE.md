# CLAUDE.md

> **CRITICAL: Write all output and all artifacts in ASD-STE100 Simplified
> Technical English.** This rule applies to the README, `INSTALL.md`, man pages,
> `.pod` sidecars, code comments, commit messages, and chat replies. Use the
> active voice and the approved words. Keep each instruction shorter than 20
> words and each descriptive sentence shorter than 25 words. Write one
> instruction in each sentence. Do not change technical names, commands, or code
> examples.

Fugu is a library of generic OpenBSD-style daemon utilities for Perl (v5.36,
core Perl, no runtime dependencies): daemonize, privilege drop, signals,
logging, process control, state, pledge/unveil, the imsg transport, and mdnsd
control. The repository also ships `Protocol::Imsg`, the imsg(3) frame codec.
OpenBSD is the production platform; Linux and Darwin are supported for
development and CI.

The consumers are the sibling repositories OpenHAP, FuguVM, and FuguWeb. Each
installs the latest release tarball of this repository through its dependency
manifests. Keep Fugu generic: no consumer policy belongs here.

The repo holds two Perl namespaces:

- `Fugu::` (`lib/Fugu/`) — the utility nexus, one concern per module
- `Protocol::Imsg` (`lib/Protocol/Imsg.pm`) — the imsg(3) frame, as bytes; a
  codec with no socket in it

The dependency direction is one way. `Protocol::` uses core Perl only, and never
`Fugu::` or `App::`. `Fugu::` uses core Perl, its optional CPAN libraries, and
the `Protocol::` codecs on an allowlist, and never `App::`.
`t/protocol/boundary.t` enforces both directions.

Fugu loads with core Perl only: `t/fugu/coreperl.t` proves it. Every CPAN use is
a lazy `require` behind an optional feature (`Net::SSH2` in `Fugu::SSH`,
`Net::MQTT::Simple` in `Fugu::MQTT`, the HTTP stack in `Fugu::Proxy`).

## Commands

```sh
make check          # lint + test + tidy + spec-coverage; MUST pass before every commit
make test           # prove -l -v t/{fugu,protocol,conformance,scripts,ci}/*.t
prove -l t/fugu/foo.t      # run a single test file
make lint           # Perl::Critic, severity 4
make spec-coverage  # spec/ section coverage + stale-citation check

make tidy           # check perltidy formatting
make tidy-fix       # auto-fix Perl formatting
make prettier       # check Markdown/JSON/YAML formatting
make prettier-fix   # auto-fix Markdown/JSON/YAML
make deps           # install runtime dependencies (none today)
make deps-test      # runtime + test dependencies
make deps-develop   # all dependencies
make dist           # build the release tarball, a standard Perl distribution
```

## Layout

- `lib/Fugu/` and `lib/Protocol/` — the modules, each with a `.pod` sidecar
- `t/fugu/`, `t/protocol/` — unit tests; `t/conformance/` — spec-cited
  conformance tests; `t/scripts/`, `t/ci/` — tooling tests, named after what
  they drive (see `t/CLAUDE.md`)
- `spec/` — the mdnsd control protocol references, normative for the conformance
  tier (see `spec/CLAUDE.md`)
- `deps/` — per-OS dependency manifests; `scripts/` — the dependency, download,
  coverage and dist helpers (`deps`, `ftp`, `spec-coverage`, `dist`)
- `.github/actions/` — the canonical CI actions (`setup-perl`, `gh-release`,
  `pause-upload`); the sibling repositories reference them as
  `FuguBSD/Fugu/.github/actions/<name>@main`

## Coding style

OpenBSD style(9): 8-character tabs, continuation lines indent 4 spaces.
Formatting is enforced by `make tidy` and `make lint` — run `make tidy-fix`
rather than hand-formatting. `.perlcriticrc` deliberately relaxes many rules to
match OpenBSD style; do not "fix" code toward generic Perl::Critic defaults.

Rules the tools cannot enforce:

- Always `use v5.36` (enables strict, warnings, say, signatures) — the only
  exception is `scripts/deps`, see Dependencies
- Object-oriented style with signatures; object is `$self`; internal methods
  prefixed with `_`; do not name unused parameters: `sub foo($, $) { }`
- Function brace on its own line, control-structure brace on the same line:

```perl
sub method($self, $param)
{
	if ($condition) {
		...
	}
	return $result;
}
```

- Explicit `return` except for no-return or constant methods; omit parens on
  zero-argument method calls: `$object->width`
- Inheritance via `our @ISA` (not `use parent`); no multiple inheritance;
  multiple related packages per file are fine; constants via `use constant`
- New files start with the `# ex:ts=8 sw=4:` modeline and ISC copyright header —
  copy from an existing file in `lib/`
- `Class->new`, never indirect object notation; code refs always with
  parentheses (except delegation); no old-style prototypes unless creating
  syntax
- Simple string operations over regex where they suffice; `wantarray()` only as
  an optimization, never to change semantics

## Error handling and security

- Return `undef` (bare `return`) for recoverable errors, `die` for programming
  errors; never use `eval` for flow control
- Never ignore return values of system calls:
  `open my $fh, '<', $file or do { warn "..."; return; };`
- No threads — multiplex with `IO::Select`
- Security by default: randomness from `/dev/urandom`, design for
  pledge(2)/unveil(2), fail closed, never trust external input
- Fail cleanly: diagnose invalid input in a human-readable message, never a
  stack trace; leave no partial files, orphaned processes, or corrupt state
  behind; make repeatable operations truly idempotent

## Simplicity

- Delete old code paths outright; never keep an alias, a bridge, or a migration.
- Do not keep test-only API. Delete a sub or option that only tests use,
  together with its test.
- Validate each input once, at its boundary. Do not check the same invariant
  again downstream.
- This repository is a library, so its tests are its callers of record:
  `t/scripts/symbols.t` fails on a sub that no module and no test names.

## Testing

- Unit tests use `Test::More` with `done_testing()`; they skip gracefully when a
  dependency is unavailable (`plan skip_all => ...`); mirror an existing test in
  `t/fugu/` when adding one
- Be resilient to timing variations
- Every feature needs tests

## Documentation

Every fact lives in exactly one place; everything else points to it. Decide
placement top-down — first match wins:

| #   | The content is...                               | It belongs in...                                                |
| --- | ----------------------------------------------- | --------------------------------------------------------------- |
| 1   | for human end-users or operators                | `README.md` (intro, quick start), `INSTALL.md` (install, setup) |
| 2   | the API of a Perl module                        | sidecar `.pod` next to the `.pm` — never inline POD             |
| 3   | needed on essentially every coding task         | this file — always loaded, so keep it short                     |
| 4   | needed only when touching one directory's files | that directory's `CLAUDE.md`                                    |
| 5   | none of the above                               | nowhere — delete it                                             |

Corollaries:

- No `README.md` anywhere except the repository root
- A new `lib/` module needs a `.pod` sidecar and a test
- An installed program or config format would get an mdoc(7) man page; this
  repository ships none
- Update the relevant documentation with any change in behavior, options, or
  configuration

## Dependencies

`deps/{OpenBSD,Linux,Darwin}.txt` are authoritative, installed by `make deps`
via `scripts/deps`; one line each, `<environment> <type> <name>`, where
`<environment>` is `runtime`, `test`, or `develop` and `<type>` is `pkg`,
`dist`, or `cpan`. A `dist` line names a release-asset URL, and `scripts/deps`
installs the tarball with cpanm. The runtime tier of this repository is empty by
contract.

`scripts/deps` is the one exception to `use v5.36`: it runs before anything is
installed, and macOS still ships perl 5.34. It uses `use v5.34` plus explicit
`use warnings` and core modules only. Do not "fix" it up to 5.36.

- Justify the need first: prefer base-system Perl, and `require` optional
  dependencies so they stay optional
- Prefer `pkg` over `cpan` — OS packages are vetted, binary, and upgraded with
  the system (on OpenBSD the native `p5-*` packages)
- Add the line to every platform manifest that applies, keep the `cpanfile` in
  sync, then verify with `make deps` and commit with the `build` type

## Releases

Releases use semantic versioning: the tag is `v<MAJOR>.<MINOR>.<PATCH>` and the
dist version drops the `v`. There is no VERSION file and no `$VERSION` in a
source module — the version derives from the latest `v*` tag, and the dist build
stamps `our $VERSION` into every package it stages. `make dist` builds a
standard Perl distribution tarball (`scripts/dist` writes its `Makefile.PL` and
`MANIFEST` into the staged tree only).

The Build workflow builds the dist on every merged commit and keeps it as a
workflow artifact — it releases nothing. A release is deliberate: push a
`v<MAJOR>.<MINOR>.<PATCH>` tag (`git tag v0.1.0 && git push origin v0.1.0`) and
the Release workflow tests, builds once, and publishes the one tarball in
separate steps: to GitHub Releases — under its versioned name and as
`Fugu.tar.gz`, the stable asset that `releases/latest/download/Fugu.tar.gz`
serves to the consumers — and to PAUSE, with the `PAUSE_USERNAME` and
`PAUSE_PASSWORD` secrets from the `release` environment.

CI uses no third-party action: GitHub's own `actions/`, this repository's
composite actions (`setup-perl`, `gh-release`, `pause-upload` — the canonical
copies every FuguBSD repository references), and local paths only.
`t/ci/setup-perl.t` enforces it.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):
`<type>(<scope>): <description>` with types `feat`, `fix`, `docs`, `style`,
`refactor`, `perf`, `test`, `build`, `ci`, `chore` and module scopes such as
`file`, `imsg`, `log`, `mdnsd`, `mqtt`, `process`, `proxy`, `ssh`. Breaking
changes take `!` or a `BREAKING CHANGE:` footer.

Always run `make check` before committing; fix formatting failures with
`make tidy-fix`. Group unrelated changes into separate commits rather than one
sweeping commit.

## Gotchas

- Use `explore/` (gitignored) for scratch scripts and experiments, never `/tmp`
- Audit findings go to `SCRATCHPAD-<N>.md` files (gitignored)
