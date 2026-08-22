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

<a id="rel-assets"></a>

## Release assets

A release is deliberate: push a version tag, and the release workflow tests,
builds once, and publishes the one tarball.

- **REL-ASSETS-1** — The workflow must publish the tarball to GitHub Releases
  under its versioned name and as `Fugu.tar.gz`, the stable asset that
  `releases/latest/download/Fugu.tar.gz` serves to the consumers.
- **REL-ASSETS-2** — The workflow must publish the same tarball to PAUSE, with
  the `PAUSE_USERNAME` and `PAUSE_PASSWORD` secrets from the `release`
  environment.

<a id="rel-build"></a>

## The build pipeline

- **REL-BUILD-1** — The build workflow must build the dist on every merged
  commit and must keep it as a workflow artifact. It releases nothing.
