# Fugu

Generic OpenBSD-style daemon utilities for Perl.

Fugu gives a Perl daemon the plumbing that OpenBSD daemons share: daemonize,
privilege drop, signal handling, logging, process control, PID files, state
files, pledge(2)/unveil(2), signify(1) signature verification, an event loop, a
caching HTTP proxy, SSH and MQTT clients, and a native mdnsd(8) control client.
The distribution also ships `Protocol::Imsg`, a sans-IO codec for the imsg(3)
frame.

Fugu needs core Perl only (v5.36). Every CPAN module it can use is an optional
feature, loaded lazily. OpenBSD is the production platform; Linux and Darwin
serve development and CI. The specification in [spec/](spec/index.md) states the
design; the consumers install the latest release tarball through their
dependency manifests.

## Quick start

```sh
make deps-test
make check
doas make install
```

`make install` puts the modules and their `.pod` sidecars under the site_perl
tree, found by `perldoc Fugu::Daemon`.

Each release also carries a standard Perl distribution tarball. Install it with
cpanm:

```sh
cpanm --notest https://github.com/FuguBSD/Fugu/releases/latest/download/Fugu.tar.gz
```

See [INSTALL.md](INSTALL.md) for full instructions.

## Layout

- `lib/Fugu/`, `lib/Protocol/` — the modules, each with a `.pod` sidecar
- `spec/` — the specification; `spec/protocol/` — the curated protocol
  references that the conformance tier cites
- `t/fugu/`, `t/protocol/` — unit tests; `t/conformance/` — spec-cited
  conformance tests; `t/scripts/`, `t/ci/` — tooling tests (see `t/CLAUDE.md`)
- `deps/` — per-OS dependency manifests, one line each, installed by
  `make deps`; `scripts/` — the dependency, download, coverage, check and dist
  helpers

## Documentation

Each module documents its API in a `.pod` sidecar. Start with:

- `perldoc Fugu::Daemon` — daemonize a process
- `perldoc Fugu::Log` — the unified logger
- `perldoc Fugu::EventLoop` — one IO::Select loop for a single-process daemon

## Commands

```sh
make check          # lint + format + test + spec-coverage + spec-check + ste-lint
make test           # prove -l over every test tier
prove -l t/fugu/foo.t      # one test file
make format-fix     # auto-fix Perl formatting
make format-md      # Markdown/JSON/YAML formatting check
make dist           # build the release tarball
```

## Releases

Push a `v<MAJOR>.<MINOR>.<PATCH>` tag, and the release workflow publishes the
tarball to GitHub Releases and to PAUSE. The rules are in
[spec/release.md](spec/release.md).

## Commit scopes

`file`, `imsg`, `log`, `mdnsd`, `mqtt`, `privdrop`, `process`, `proxy`, `repl`,
`signify`, `ssh`, `spec`, `deps`, `ci`.

## License

ISC. See [LICENSE](LICENSE).
