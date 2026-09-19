# Versioning and release

This document specifies the version scheme, the release assets, and the build
pipeline.

<a id="rel-version"></a>

## Versioning

- **REL-VERSION-1** — A release tag is `v<MAJOR>.<MINOR>.<PATCH>`, and the dist
  version drops the `v`.
- **REL-VERSION-2** — No `VERSION` file and no `$VERSION` exists in a source
  module. The version derives from the latest `v*` tag, and the dist build
  stamps `our $VERSION` into every package that it stages.
- **REL-VERSION-3** — `make dist` must build a standard Perl distribution
  tarball. The staged tree alone holds the generated `Makefile.PL` and
  `MANIFEST`.
- **REL-VERSION-4** — The distribution must declare the perl floor of
  ARC-COREPERL-3. The `dist.perl` key of `.toolingrc` names that floor, and the
  dist build stamps it into `Makefile.PL` and `META.json`. A perl that installs
  the distribution must run the code.

<a id="rel-assets"></a>

## Release assets

A release is deliberate: push a version tag, and the release workflow tests,
builds once, and publishes the one tarball.

- **REL-ASSETS-1** — The workflow must publish the tarball to GitHub Releases,
  under its versioned name and as `Fugu.tar.gz`. The consumers fetch that stable
  asset from `releases/latest/download/Fugu.tar.gz`.
- **REL-ASSETS-2** — The workflow must publish the same tarball to PAUSE, with
  the `PAUSE_USERNAME` and `PAUSE_PASSWORD` secrets from the `release`
  environment.

<a id="rel-build"></a>

## The build pipeline

- **REL-BUILD-1** — The build workflow must build the dist on every merged
  commit and must keep it as a workflow artifact. It releases nothing.

<a id="rel-port"></a>

## The OpenBSD port

- **REL-PORT-1** — The repository holds the OpenBSD port `devel/p5-Fugu` under
  `ports/devel/p5-Fugu`. The submission to the ports tree is the operator's act.
- **REL-PORT-2** — The port must build from the distribution tarball on CPAN
  through the `cpan` port module. It must pin one released version and its
  checksums, and a change after a release updates the pin.
- **REL-PORT-3** — The port must declare no run dependency outside the base
  system, because the library loads with core Perl only
  ([ARC-COREPERL](architecture.md#arc-coreperl)). A test dependency can name a
  tool that a test drives.
- **REL-PORT-4** — The test target of the port must run the test suite of the
  tarball. Every test must pass or skip in the port build.
- **REL-PORT-5** — The developer must build the port on OpenBSD/amd64 and on
  OpenBSD/arm64, and must run the test target there. The `fuguvm` tool can
  supply the guest, as a command only. The port must not depend on `fuguvm`.

FuguPass PROG-PORT and FuguTTX HRN-PKG name the package as a run dependency, so
this port precedes those ports in the tree.
