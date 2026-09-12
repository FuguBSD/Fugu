# 013 — Fugu::X509

## Status

Proposed. It can land now. FuguWeb WEB-X509 waits on it.

Implements: LIB-X509. Extends: LIB-KEYDIR.

## Purpose

A key directory publishes a code signing certificate beside its signify keys and
its OpenPGP keys, per FuguWeb WEB-X509. No module of Fugu reads a certificate,
computes its fingerprint, or makes a signature with its private key.

This plan adds `Fugu::X509`. The module decodes PEM and DER, reads the subject,
the issuer and the validity, and computes the SHA-256 fingerprint, with no
command. It makes and verifies a detached CMS signature through `openssl(1)`.

## Evidence

`Fugu::OpenPGP` shows the shape of the byte reader. It holds an armor decoder, a
fingerprint over the decoded bytes, and a clean failure for a wide string. A
certificate takes the same shape. The PEM block is base64 with two delimiter
lines and no checksum. The DER is a small set of tags: `SEQUENCE`, `SET`,
`OBJECT IDENTIFIER`, two time forms, and three string forms.

The research reads the Apple documents. A Developer ID certificate lives five
years, and the leaf hash changes at each renewal. The designated requirement of
Apple pins the team identifier in the subject. The reader therefore answers the
subject as a map of attribute type to value. A caller reads the common name and
the organizational unit by name.

`openssl cms` makes a detached signature with `-sign -binary`, and verifies one
with `-verify -binary -content`. The pair `-nointern -certfile` makes the
verifier read the one certificate that the caller names, and `-noverify` checks
no chain. LIB-X509-3 rests on those three options.

## The rule changes

### LIB-KEYDIR

- The extension table gains `pem` for the type `x509`. A binding by an X.509
  signer takes the extension `p7s`.

## The interface

- `Fugu::X509->decode_pem($text)` answers the DER bytes, or undef with the
  reason. It takes one `CERTIFICATE` block and rejects every other block type.
- `Fugu::X509->fingerprint($der)` answers the upper-case hexadecimal SHA-256.
- `Fugu::X509->parse($der)` answers a hash reference with `subject`, `issuer`,
  `not_before` and `not_after`. Each name is a hash of attribute type to value,
  and each time is seconds since the epoch.
- `Fugu::X509->new(%args)` takes an optional `command`, resolves `openssl`, and
  answers an object. `is_available`, `command` and `command_absent` follow
  `Fugu::Signify`.
- `sign_cms(%args)` takes `certificate`, `secret` and `file`, and answers the
  PEM signature.
- `verify_cms(%args)` takes `certificate`, `file` and `signature`, and answers 1
  or undef with the reason.

## The change

1. `lib/Fugu/X509.pm` and its sidecar hold the reader and the two command
   methods.
2. `lib/Fugu/KeyDir.pm` gains the `pem` extension and the `p7s` binding
   extension.
3. `t/fugu/x509.t` covers the reader against a certificate that the test makes
   with `openssl(1)`, and covers the two command methods. It skips the command
   parts when the tool is absent.
4. `t/fugu/keydir.t` covers the new extension.
5. `spec/STATUS.md` sets LIB-X509 and keeps LIB-KEYDIR `done`.
6. This plan directory goes in the same change.

## What this plan does not do

It reads no PKCS#12 file. The caller converts one with `openssl pkcs12` before
it names the PEM private key.

It checks no chain and no revocation. The caller vouches for the certificate,
per LIB-X509-3.

It reads no extension of the certificate. The key usage and the extended key
usage stay with the issuer, and a later plan adds a reader when a caller needs
one.
