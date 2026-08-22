# Architecture

Fugu is one repository with two Perl namespaces and a one-way dependency
direction. This document specifies the namespaces, the boundary, the load
contract, and the caller rule.

<a id="arc-namespaces"></a>

## Namespaces

- **ARC-NAMESPACES-1** — `Fugu::` (`lib/Fugu/`) is the utility nexus, with one
  concern per module.
- **ARC-NAMESPACES-2** — `Protocol::` (`lib/Protocol/`) holds wire codecs with
  no socket in them.
- **ARC-NAMESPACES-3** — Every module must have a `.pod` sidecar and a test.

<a id="arc-boundary"></a>

## The dependency boundary

The dependency direction is one way.

- **ARC-BOUNDARY-1** — `Protocol::` must use core Perl only, and must not use
  `Fugu::` or `App::`.
- **ARC-BOUNDARY-2** — `Fugu::` must use only core Perl, its optional CPAN
  libraries, and the `Protocol::` codecs on an allowlist. It must not use
  `App::`.

<a id="arc-coreperl"></a>

## The load contract

- **ARC-COREPERL-1** — Fugu must load with core Perl only.
- **ARC-COREPERL-2** — Every CPAN use must be a lazy `require` behind an
  optional feature: `Net::SSH2` in `Fugu::SSH`, `Net::MQTT::Simple` in
  `Fugu::MQTT`, and the HTTP stack in `Fugu::Proxy`.

<a id="arc-callers"></a>

## The caller rule

This repository is a library, so its tests are its callers of record.

- **ARC-CALLERS-1** — Every sub in `lib/` must have a caller in `lib/` or in a
  test.

<a id="arc-generic"></a>

## Genericity

Fugu stays generic. No consumer policy belongs here. A consumer installs the
latest release tarball through its dependency manifests.
