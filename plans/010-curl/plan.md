# 010 — Fugu::Curl: one downloader over curl, wget, and ftp

## Status

Proposed. It can land now, and it depends on no other plan.

Implements: LIB-CURL.

## Purpose

Core Perl fetches no HTTPS URL. `HTTP::Tiny` is core, but its TLS needs
`IO::Socket::SSL`, which is not. Every FuguBSD repository ships the shell helper
`scripts/ftp` for that reason, and FuguVM installs a copy into its share tree.
The helper picks one command by the name of the operating system. A Linux host
without wget fails, even when curl is there. An HTTP error without the fail flag
of curl exits zero and writes the error page as the file.

This plan adds `Fugu::Curl`. The module picks the first command that the host
has, in the order curl, wget, ftp. It fails closed on an HTTP error, it leaves
no partial file, and it reports what failed and why.

## Why Fugu holds this work

A downloader is generic plumbing, and two consumers need it today. FuguBench
packs Fugu, and its dependency installer fetches every release asset through the
module. FuguVM ships the shell helper in its share tree and replaces it. The
policy of the organization for a download then lives in one module, with one
test.

## Consumers

| Repo      | Need                                                                      |
| --------- | ------------------------------------------------------------------------- |
| FuguBench | Fetch a release asset, a signed manifest, and the cpanm script            |
| FuguVM    | Replace the copy of `scripts/ftp` in the share tree                       |
| Tooling   | None now. The org pack drops `scripts/ftp` when FuguBench replaces `deps` |

## Scope

In scope:

- The module, its `.pod` sidecar, and its test.

Out of scope:

- The shell helper of the org pack. Tooling retires it in a plan of its own.
- A resumed download, a parallel download, and a retry policy.
- A checksum or a signature check. `Fugu::Signify` holds both.
- A pure-Perl HTTP client. The commands hold the TLS stack of the host.

## Constraints that shape the design

**Three commands, three dialects.** Each command needs its own flags for the
same four demands. The demands are: follow a redirect, fail on an HTTP error,
write to a named file, and stop after a time limit.

| Command | Flags                                                                                        |
| ------- | -------------------------------------------------------------------------------------------- |
| curl    | `--fail --location --silent --show-error --max-time N --output TMP --write-out %{http_code}` |
| wget    | `--no-verbose --tries=1 --timeout=N --output-document=TMP`                                   |
| ftp     | `-V -M -w N -o TMP`                                                                          |

curl writes the HTTP status to standard output through `--write-out`, and
`--fail` keeps that report. The exit code of curl tells little: a 404 through a
redirect exits 56, and the manual names 22. wget follows a redirect by default,
it names the HTTP status on standard error, and it has no timeout exit code. The
ftp(1) of OpenBSD follows a redirect, verifies TLS against `/etc/ssl/cert.pem`,
exits 1 on every failure, and names the status on standard error.

**One classification for three dialects.** The module reads the HTTP status
where the command reports one, and `code` holds it. The time bound of the module
gives the status `timeout`. Every failure that the command does not report takes
the status `network`.

**TLS verification stays on.** Each command verifies the certificate by default.
The module passes no flag that turns it off, and a test reads each argument list
for such a flag.

**A failed fetch leaves no file.** The module writes to a temporary name in the
destination directory and renames it on success. A failure removes the temporary
file. A reader of the destination therefore sees the old file or the new file,
and never a partial one.

**The proxy variables pass through.** `Fugu::Process->run` gives the child the
environment of the parent unless the caller sets `env`. The module sets no
`env`, so `http_proxy`, `https_proxy`, `ftp_proxy`, and `no_proxy` reach the
command. A host behind a proxy reaches a release through them.

**Two time limits.** The `timeout` of `Fugu::Process->run` bounds the process,
and the command flag bounds the transfer 30 seconds later. The module therefore
ends the fetch first, and it reports the status `timeout` for every dialect.

**The load contract.** The module uses `Fugu::Process` and `Fugu::File`, and
core Perl. ARC-COREPERL-1 holds with no lazy `require`.

**The caller rule.** ARC-CALLERS-1 states that every sub in `lib/` must have a
caller in `lib/` or in a test. Each sub of this plan gets a test.

## The interface contract

`Fugu::Curl->new(%args)` builds a downloader. The option `command` names a
command or an absolute path. Without it, the method walks `PATH` for `curl`,
then `wget`, then `ftp`. The option `timeout` sets the transfer bound in
seconds, with the default 600. The method resolves the command once, and it runs
no process.

`is_available` returns 1 when the object resolved a command, and 0 otherwise.
`command` returns the resolved path, or undef.

`fetch($url, $path)` downloads the URL to the path. It returns 1 on success, and
undef on every failure. After a call, `status` holds one of `ok`, `http`,
`network`, `timeout`, and `absent`. `code` holds the HTTP status when the
command reported one, and undef otherwise. `error` holds the reason, with the
command name and the URL.

`arguments($url, $tmp)` returns the argument list that `fetch` runs for the
resolved command. The method runs no process. A test reads the list for each
dialect, on a host that has one of the three commands only.

## Files

| File                | Change                         |
| ------------------- | ------------------------------ |
| `lib/Fugu/Curl.pm`  | New: the downloader            |
| `lib/Fugu/Curl.pod` | New: the API contract          |
| `t/fugu/curl.t`     | New: the tests of `Fugu::Curl` |
| `spec/STATUS.md`    | The `LIB-CURL` row to `done`   |

## Tests

The test reaches no network. It starts a server on the loopback interface with
`IO::Socket::INET`, which is core, and the server answers each request with a
canned response. A test of one command runs when `PATH` holds that command, and
it skips otherwise. The Linux runner of CI holds curl and wget, and a macOS host
holds curl.

`t/fugu/curl.t` covers:

- `new` without a command resolves the first command of the order, and
  `is_available` returns 1.
- `new` with an empty `PATH` resolves nothing. `is_available` returns 0, and
  `fetch` returns undef with the status `absent`.
- `arguments` for each of the three dialects, through the `command` option with
  a stub path for the commands that the host lacks. No list holds a flag that
  turns TLS verification off.
- A 200 answer lands at the destination, and no temporary file stays.
- A 404 answer returns undef with the status `http` and the code 404, and no
  file appears at the destination.
- A 302 answer to a 200 answer lands at the destination.
- A server that never answers returns undef with the status `timeout`, under a
  `timeout` of one second. The time bound of the module gives that status, and
  never an exit code of a dialect.
- A closed port returns undef with the status `network`.
- A destination that exists holds the old bytes after a failure, and the new
  bytes after a success.

## Acceptance

- `make check` passes.
- Each new sub has a caller in a test, per ARC-CALLERS-1.
- The module has a `.pod` sidecar and a test, per ARC-NAMESPACES-3.
- `t/fugu/coreperl.t` loads `Fugu::Curl` with the pruned `@INC`.
- The `LIB-CURL` row is `done`.
- The change deletes this plan.

## Open questions

None. The name `Fugu::Curl` names the first command of the order, and the
operator chose it on 2026-09-10. The sidecar states that the module is a
downloader over three commands.
