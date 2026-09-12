# 011 — The signify signer and the binding names

## Status

Proposed. It can land now. FuguWeb WEB-TRUST waits on it.

Extends: LIB-SIGNIFY. Extends: LIB-KEYDIR.

## Purpose

`Fugu::Signify` verifies a signature and reads and writes a manifest, and it
signs nothing. The rotation of FuguWeb runs `signify -G` and `signify -S` on its
own, so the one generic signer of the organization lives in an application.

A key directory gains a root of trust and a binding for each other key, per
FuguWeb WEB-TRUST. The name pattern of a binding, the retention rule and the
root rule are generic. `Fugu::KeyDir` holds every other generic part of that
directory.

This plan moves the signer and the generator into `Fugu::Signify`, and adds the
binding names and the root rule to `Fugu::KeyDir`.

## Evidence

`Fugu::Signify` verifies with two engines, per LIB-SIGNIFY-2. The `perl` engine
uses `Fugu::Ed25519`, and the `signify` engine runs the command through
`Fugu::Process` with an argument list. LIB-ED25519-6 keeps every private key
operation out of Perl, so the signer and the generator run the command under
either engine.

The comment of the module states that a signature is a human act. The rotation
of FuguWeb signs in a workflow, with no human, so the statement does not
describe the design. The rule of LIB-SIGNIFY that the module cannot sign changes
with this plan.

`Fugu::KeyDir` parses a key name into its parts and builds one back, so the two
stay inverses. A binding name takes the same pair of methods.

## The rule changes

### LIB-SIGNIFY

- The unit text names a signer and a generator. The module holds no private key
  of its own: a caller names each key file.
- A new rule: the signer and the generator take each private half as a path, and
  run the command with an argument list. Neither one logs the bytes of a key.
- A new rule: the signer and the generator must run signify(1) under either
  engine, per LIB-ED25519-6. Under the `perl` engine, `command_absent` must tell
  an absent command for the two methods alone.
- A new rule: the generator must make a pair with no passphrase. It must write
  the private half with no group mode and no other mode.

### LIB-KEYDIR

- A new rule: the binding name is `<target file>.<signer stem>.<ext>`. The
  extension follows the type of the signer: `sig`, `asc` or `p7s`. The parser
  and the builder must stay inverses.
- A new rule: a directory holds exactly one `current` key of the purpose `root`,
  and that key is a signify key. A directory with no key is the exception. A
  caller that mints the first root asks for the rule apart from the status rule.
- A new rule: the retention rule of a binding. A signer that is `current` or
  `next` targets the current root. A signer that is `retired` targets a key of
  its own purpose with a higher serial.

## The interface

### Fugu::Signify

- `generate(%args)` takes `comment`, `public` and `secret`, and runs
  `signify -G -n`. It answers 1, or undef with the reason in `error`.
- `sign(%args)` takes `secret`, `file` and `signature`, and runs `signify -S`.
  It answers 1, or undef with the reason.
- `command_absent` tells an absent command for both. Under the `perl` engine
  `verify` never sets it, and the two methods do.

### Fugu::KeyDir

- `parse_binding($filename)` answers a hash reference with `target`, `signer`
  and `type`, or undef with the reason. The target is a key file name, and the
  signer is a key stem, and both parse under `parse_name`.
- `binding_for(%args)` takes `target` and `signer`, and answers the file name.
- `check_root($keys)` holds a set to the root rule. It answers 1, or undef with
  the reason.
- `check_bindings($keys, $bindings)` holds each binding to the retention rule.
- `ROOT_PURPOSE` is the constant `root`.

## The change

1. `lib/Fugu/Signify.pm` and its sidecar gain `generate` and `sign`, and the
   comment drops the statement about a human act.
2. `lib/Fugu/KeyDir.pm` and its sidecar gain the binding names, the root rule
   and the retention rule.
3. `t/fugu/signify.t` covers the two methods against the real `signify(1)`, and
   skips when the tool is absent, as the verifier tests do.
4. `t/fugu/keydir.t` covers each new method, and the inverse of the two name
   methods.
5. `spec/library.md` carries the rule changes, and `spec/STATUS.md` keeps both
   units `done`.
6. This plan directory goes in the same change.

## What this plan does not do

It runs no `gpg(1)` and no `openssl(1)`. Plan 012 and plan 013 hold those.

It adds no `pem` extension. Plan 013 adds it with the reader that decodes the
file.
