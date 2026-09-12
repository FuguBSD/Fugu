# 012 — The OpenPGP generator and the detached signature

## Status

Proposed. It can land now. FuguWeb WEB-OPENPGP waits on it.

Extends: LIB-OPENPGP.

## Purpose

`Fugu::OpenPGP` reads an armored public key as bytes, with no command. A key
directory that mints an OpenPGP key and binds it to a root needs four more acts.
Those are: generate a key, export both halves, make a detached signature, and
verify one. Each act needs `gpg(1)`.

This plan adds the command parts to `Fugu::OpenPGP`. Each run takes a temporary
home that dies with the run. The home of the user stays untouched, and a test
never reads a real keyring.

## Evidence

`Fugu::Signify` shows the shape. An object resolves the command once, runs it
through `Fugu::Process` with an argument list, and tells an absent command from
a failed run. The byte parts of `Fugu::OpenPGP` stay class methods, because they
hold no state.

The research names two practices for this key type. An expiry protects a key
whose holder goes away, and a transition statement carries both keys through a
rotation. The expiry is an argument of the generator. The statement is a binding
in FuguWeb WEB-TRUST, so this module makes and verifies a detached signature and
no statement of its own.

## The rule changes

### LIB-OPENPGP

- The unit text names the generator, the export and the detached signature,
  through `gpg(1)`, beside the byte reader.
- A new rule: each run of `gpg(1)` must take a temporary home that the run
  removes. The module must read no home of the user, and no agent.
- A new rule: the generator must make one Ed25519 key with one user id. It sets
  an expiry when the caller names one, and none when the caller names none.
- A new rule: the verifier must import the one public key of the signer into an
  empty home. A signature of another key must fail.
- A new rule: the module must never log the armored secret half, and must write
  it with no group mode and no other mode.

## The interface

- `Fugu::OpenPGP->new(%args)` takes an optional `command`, resolves `gpg`, and
  answers an object. `is_available`, `command` and `command_absent` follow
  `Fugu::Signify`.
- `generate(%args)` takes `email` and an optional `expires`, and answers a hash
  reference with `public`, `secret` and `fingerprint`. The two halves are
  armored text.
- `sign_detached(%args)` takes `secret` and `file`, and answers the armored
  signature.
- `verify_detached(%args)` takes `public`, `file` and `signature`, and answers 1
  or undef with the reason.
- `expiry($public)` answers the expiry of the key as seconds since the epoch. It
  answers undef when the key holds none, and an empty list with the reason on a
  failure.

## The change

1. `lib/Fugu/OpenPGP.pm` and its sidecar gain the object, the four methods and
   the temporary home.
2. `t/fugu/openpgp.t` covers each method against the real `gpg(1)`, with a
   generated key, and skips when the tool is absent.
3. `deps/Linux.txt` and `deps/Darwin.txt` take `test pkg gnupg`.
4. `spec/library.md` carries the rule changes, and `spec/STATUS.md` keeps the
   unit `done`.
5. This plan directory goes in the same change.

## What this plan does not do

It makes no revocation certificate, and it edits no user id. A retired key stays
published in the directory, and a compromise takes a human decision.

It reads the expiry through `gpg(1)`. A reader of the self-signature subpackets
in Perl is a larger change than the need, and the command is present wherever
the generator is.
