# 011 — The signify signer and the binding names

## Status

Proposed. It can land now. FuguWeb WEB-TRUST and plan 013 wait on it.

Extends: LIB-SIGNIFY. Extends: LIB-KEYDIR. Extends: LIB-ED25519.

## Purpose

`Fugu::Signify` verifies a signature and reads and writes a manifest, and it
signs nothing. The rotation of FuguWeb runs `signify -G` and `signify -S` on its
own, so the one generic signer of the organization lives in an application.

A key directory gains a root of trust and a binding for each other key, per
FuguWeb WEB-TRUST. The name pattern of a binding and the retention rule are
generic. The root rule is consumer policy: FuguWeb WEB-TRUST-1 holds it, and
`Fugu::KeyDir` holds no purpose constant, per LIB-KEYDIR-3.

This plan moves the signer and the generator into `Fugu::Signify`, and adds the
binding names and the retention rule to `Fugu::KeyDir`.

## Evidence

`Fugu::Signify` verifies with two engines, per LIB-SIGNIFY-2. The `perl` engine
uses `Fugu::Ed25519`, and the `signify` engine runs the command through
`Fugu::Process` with an argument list. LIB-ED25519-6 keeps every private key
operation out of Perl, so the signer and the generator run the command under
either engine.

LIB-ED25519-6, the comment of each module, and the sidecar of each module state
that a signature is a human act. The rotation of FuguWeb signs in a workflow,
with no human, so the statement does not describe the design. The rule of
LIB-SIGNIFY that the module cannot sign changes with this plan.

`Fugu::Signify->new` dies when the `keys` list is absent or empty. A first root
mint holds no public key yet, so it cannot build the object that runs
`generate`.

`Fugu::KeyDir` parses a key name into its parts and builds one back, so the two
stay inverses. A binding name takes the same pair of methods.

## The rule changes

### LIB-SIGNIFY

- The unit text names a signer and a generator. The module holds no private key
  of its own: a caller names each key file.
- The text of LIB-SIGNIFY-2 changes. Its three accessors describe verification
  alone: under the `perl` engine `is_available` returns 1, `command` returns
  undef, and `command_absent` returns 0.
- A new rule: `generate` and `sign` must run signify(1) under either engine, per
  LIB-ED25519-6. Each one resolves the command itself. On an absent command the
  method must return undef, must set `error`, and `command_absent` must report 1
  for that call.
- A new rule: the signer and the generator take each private half as a path, and
  run the command with an argument list. Neither one logs the bytes of a key.
- A new rule: the generator must make a pair with no passphrase. It must write
  the private half with no group mode and no other mode.
- A new rule: `new` must take an absent or empty `keys` list. A caller then
  reaches the signer or the generator with no public key. `verify` and
  `verify_manifest` must die on such an object.

### LIB-ED25519

- The text of LIB-ED25519-6 changes. It keeps "must hold no private key
  operation", and it drops "A signature is a human act, and signify(1) makes
  it". The rationale becomes: a private key operation stays with signify(1),
  which the signer of `Fugu::Signify` runs.

### LIB-KEYDIR

- A new rule: the binding name is `<target file>.<signer stem>.<ext>`. The
  extension follows the type table of `Fugu::KeyDir`: `sig` for a signify
  signer, and `asc` for an OpenPGP signer. A later type adds its own extension.
  The parser and the builder must stay inverses.
- A new rule: the retention rule of a binding. The caller names the current root
  key. A signer that is `current` or `next` targets that root. A signer that is
  `retired` targets a key of its own purpose with a higher serial.

## The interface

### Fugu::Signify

- `new(%args)` takes an absent or empty `keys` list. `verify` and
  `verify_manifest` die on such an object.
- `generate(%args)` takes `comment`, `public` and `secret`, and runs
  `signify -G -n`. It answers 1, or undef with the reason in `error`.
- `sign(%args)` takes `secret`, `file` and `signature`, and runs `signify -S`.
  It answers 1, or undef with the reason.
- `generate` and `sign` each resolve the command under either engine. On an
  absent command `command_absent` reports 1 for that call.

### Fugu::KeyDir

- `parse_binding($filename)` answers a hash reference with `target`, `signer`
  and `type`, or undef with the reason. The target is a key file name, and the
  signer is a key stem, and both parse under `parse_name`.
- `binding_for(%args)` takes `target` and `signer`, and answers the file name.
- `check_bindings($keys, $bindings, $root)` holds each binding to the retention
  rule. `$root` is the file name of the current root key, and the caller names
  it. The method answers 1, or undef with the reason.

## The change

1. `lib/Fugu/Signify.pm` and its sidecar gain `generate` and `sign`, and `new`
   takes an empty `keys` list. The comment drops the statement about a human
   act. `lib/Fugu/Signify.pod` drops the CAVEATS paragraph that holds "A
   signature is a human act, without exception".
2. `lib/Fugu/Ed25519.pm` and `lib/Fugu/Ed25519.pod` drop the sentence "A
   signature is a human act, and signify(1) makes it". Each one states that a
   private key operation stays with signify(1), which the signer of
   `Fugu::Signify` runs.
3. `lib/Fugu/KeyDir.pm` and its sidecar gain the binding names and the retention
   rule.
4. `t/fugu/signify.t` covers the two methods against the real `signify(1)`, and
   skips when the tool is absent, as the verifier tests do. It covers `new` with
   an empty `keys` list, and the death of `verify` on that object.
5. `t/fugu/keydir.t` covers each new method, and the inverse of the two name
   methods.
6. `spec/library.md` carries the rule changes, and `spec/STATUS.md` keeps the
   three units `done`.
7. This plan directory goes in the same change.

## What this plan does not do

It runs no `gpg(1)` and no `openssl(1)`. Plan 012 and plan 013 hold those.

It adds no `pem` key extension and no `p7s` binding extension. Plan 013 adds
both with the reader that decodes the file.

It holds no root rule and no `root` purpose. FuguWeb WEB-TRUST-1 holds the root
rule, and it names the root key when it calls `check_bindings`.
