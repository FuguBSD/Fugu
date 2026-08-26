# Fugu

Generic OpenBSD-style daemon utilities for Perl.

Fugu gives a Perl daemon the plumbing that OpenBSD daemons share: daemonize,
privilege drop, signal handling, logging, process control, PID files, state
files, and pledge(2)/unveil(2).

It adds an event loop, a caching HTTP proxy, SSH and MQTT clients, a native
mdnsd(8) control client, and signify(1) signature verification. The
distribution ships `Protocol::Imsg`, a sans-IO codec for the imsg(3) frame.

Fugu needs core Perl only (v5.36). Every CPAN module it can use is an optional
feature, loaded lazily. OpenBSD is the production platform; Linux and Darwin
serve development and CI.

## Quick start

```sh
make deps-test
make check
doas make install
```

`make install` puts the modules and their `.pod` sidecars under the site_perl
tree. Or install the latest release tarball with cpanm:

```sh
cpanm --notest https://github.com/FuguBSD/Fugu/releases/latest/download/Fugu.tar.gz
```

See [INSTALL.md](INSTALL.md) for full instructions.

## Documentation

The specification in [spec/](spec/index.md) states the design. Each module
documents its API in a `.pod` sidecar. Start with:

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

`control`, `file`, `imsg`, `log`, `mdnsd`, `mqtt`, `privdrop`, `process`,
`proxy`, `repl`, `signify`, `ssh`, `spec`, `deps`, `ci`.

## License

ISC. See [LICENSE](LICENSE).
