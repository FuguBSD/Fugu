# 004 — Fugu::Signify, verify a signify(1) signature and a SHA256 manifest

## Status

Proposed.

## Purpose

`Fugu::Signify` is a new module. It verifies a file against a signify(1) public
key and a signature file. It holds a small key set, so a caller can accept the
current key and the next key. It also verifies each named file of a signed
SHA256 manifest against its digest.

The module holds no private key, and it must not sign. It runs signify(1)
through `Fugu::Process->run`, with an argument list. It computes each manifest
digest with core `Digest::SHA`.

Every recoverable failure returns `undef` with a reason. An absent signify(1) is
a clean failure, and not a die.

## Why Fugu holds this work

FuguVM downloads OpenBSD files today, and it verifies none of them. Two files in
the FuguVM tree hold the evidence.

The install script answers the verification prompt of the OpenBSD installer.
`share/fuguvm/expect/install.exp` holds this block at lines 183 to 186:

```tcl
    "Continue without verification?" {
        respond "yes"
        exp_continue
    }
```

The guest therefore installs a file set that nothing verified. This plan does
not change that script. FuguVM plan 005 owns the change, and the line is the
evidence of the gap.

The miniroot download tests the size of the file and nothing more.
`App::FuguVM::Miniroot::download` holds this check:

```perl
	# Make sure that the download wrote a file
	if ( !-f $tmp_path || -z $tmp_path ) {
		warn "Download succeeded but file is empty\n";
		return;
	}
```

The method then calls `store_from_file`, so an unverified image enters the
cache. `App::FuguVM::Proxy::Cache` already caches `SHA256` and `SHA256.sig`
beside each set:

```perl
	qr{/pub/OpenBSD/\d+\.\d+/\w+/SHA256(\.sig)?$},      # Checksums
```

The mirror thus holds the manifest and the signature already. Nothing reads
them.

Hard rule 1 of the briefing decides where the code goes. A sibling application
is not a library, so a consumer must never load an `App::FuguVM` module. A
capability that a consumer needs as a library must live in `Fugu::`. FuguVM and
FuguTTX both need signature verification as a library, so the module lands here.

The work stays inside the low-level utility realm. signify(1) is an OpenBSD base
command. The module wraps that command and adds no policy: the caller supplies
the key set, the manifest and the file list. Fugu already wraps a base command
in the same way. `Fugu::SSH` runs ssh(1) in `interactive`, and `Fugu::Mdnsd`
speaks to mdnsd(8).

## Consumers and citations

| Repo    | Unit                                | Rules          | Need                                                                              |
| ------- | ----------------------------------- | -------------- | --------------------------------------------------------------------------------- |
| FuguVM  | plan 005 `mirror-coverage`          | —              | Verify each cached download of the OpenBSD mirror with `Fugu::Signify`            |
| FuguVM  | `share/fuguvm/expect/install.exp`   | —              | The script waives verification in the guest, so the host must verify              |
| FuguTTX | `HRN-FETCH` (spec/harness.md)       | — (prose only) | `ttx fetch` validates the signify signature before the model loads. Blocked by D7 |
| FuguTTX | `INF-INTEGRITY` (spec/inference.md) | — (prose only) | Each released GGUF file ships a SHA256 manifest, signed with signify(1)           |
| FuguTTX | `LIC-RELEASE` (spec/licensing.md)   | — (prose only) | A human signs each artifact and each manifest under the pinned key                |

Each citation comes from the file. Two facts about the citations need a plain
statement.

FuguVM plan 005 exists, at `plans/005-mirror-coverage/plan.md`. That plan names
this plan as its dependency: "This plan depends on Fugu plan 004. That plan
lives in the Fugu repository, at `plans/004-signify-verification/plan.md`. It
adds `Fugu::Signify`, and this plan is its first consumer."

The three FuguTTX units hold no numbered rule. `HRN-FETCH`, `INF-INTEGRITY` and
`LIC-RELEASE` each carry prose only, and the register lists each one as `open`.
The number in the register is a roadmap phase, not a rule count. The rows
therefore cite the unit anchor, and they cite no rule ID.

`HRN-FETCH` states the key-set need in one sentence:

> The project generates a key two releases ahead, and each release ships the
> public key of the next release.

A key set of two keys serves that practice exactly.

**FuguTTX is blocked today.** Decision D7 names two port dependencies: llama.cpp
and p5-Fugu, and no other. It also states that "the client loads only this
module from the distribution". That module is `Fugu::REPL`. A use of
`Fugu::Signify` in the FuguTTX harness therefore goes against D7. FuguTTX plan
001 `fugu-module-allowlist` proposes the change to D7, and it waits for a human.
This plan must not treat FuguTTX as a reachable consumer.

FuguPass and FuguOracle need no signature verification. Neither specification
names signify(1).

## Scope

In scope:

- `new`, and the `keys` and `command` arguments.
- `is_available`, `command`, `error` and `command_absent`.
- `verify($file, $sigfile)`, over the key set, in order.
- `verify_manifest(%args)`, with `manifest`, `signature` and `files`.
- The `MAX_MANIFEST_SIZE` and `SIGNIFY_TIMEOUT` constants.
- Four private helpers: `_find_command`, `_run_signify`, `_parse_manifest` and
  `_digest`.
- The `.pod` sidecar, the `Fugu.pod` index entry, and one README line.
- A `test pkg` line in `deps/Linux.txt` and in `deps/Darwin.txt`.

Out of scope:

- Signing. The module holds no private key, and it must have no `sign` method.
  FuguTTX `agents.md` states the reason: "A signature is a human act, without
  exception."
- Key generation. A caller generates a key pair with signify(1) itself.
- A key pin file, a key expiry and a rotation policy. Each one is consumer
  policy, and Fugu stays generic.
- A download. The caller fetches the file. FuguVM uses its `scripts/ftp` helper.
- A pure-Perl Ed25519 verifier. Crypto in Fugu needs a CPAN library or a large
  amount of new code. signify(1) is the trusted implementation.
- The embedded and gzip signature modes of signify(1), which are `-e` and `-z`.
  No consumer needs them.
- Another digest algorithm. OpenBSD publishes SHA256, and FuguTTX publishes
  SHA256.
- A read of `/etc/signify`. The key path comes from the caller.
- A TLS check on the download. A verified signature replaces trust in the
  transport, and that is the point of the module.

## Constraints that shape the design

**signify(1) is not on every host.** It is in OpenBSD base. It is a package on
Linux and on Darwin. The module must therefore report an absent command as a
clean failure. `new` must not die when the command is absent, and `is_available`
must report the truth before any call.

**The command name differs by platform.** On OpenBSD the command is `signify`.
On Debian and Ubuntu the `signify-openbsd` package installs the command as
`signify-openbsd`, because the name `signify` belongs to an unrelated Debian
package. The search list must therefore try `signify-openbsd` first, and
`signify` second. The OpenBSD-specific name is unambiguous, and it exists only
where the real program is installed. On OpenBSD and on Darwin the fallback finds
`signify`.

**The module must not run a shell.** `Fugu::Process->run` takes the command as a
list, so no argument needs quoting and no argument can become a shell operator.

**A verified file can be large.** An OpenBSD file set is hundreds of megabytes.
The digest must stream from a file handle, and the file must never enter memory
whole.

**The manifest check uses `Digest::SHA`, not `signify -C`.** signify(1) can
verify a signed checksum list and each file digest in one call. Three facts rule
that mode out:

1. `signify -C` resolves each file name against the working directory. FuguVM
   downloads to a `File::Temp` path, and it stores the file in the cache after
   the fact. The file therefore does not sit beside the manifest at verification
   time.
2. `signify -C` returns one exit code for the whole list. A caller needs the
   name of the file that failed.
3. `Digest::SHA` is core Perl. One `signify -V` call then covers the whole
   manifest, and the digest of each file needs no further process. A pledged
   caller thus needs one execve(2), not one for each file.

**A pledged caller needs two promises.** The module reads files, so the caller
needs `rpath`. The module runs a command, so the caller needs `proc exec`. The
module must not call `Fugu::Sandbox` itself: the pledge belongs to the program,
not to a library method.

**Taint mode needs an absolute command.** `$ENV{PATH}` is tainted, so a path
that the search list builds cannot reach execve(2) under `perl -T`. A caller
under taint mode must pass `command` as an absolute path. The `.pod` must state
this.

**The parser must not skip a line.** `Fugu::Config` never skips an unparsed
line, and the manifest parser must follow it. A line that the parser does not
understand is a failure. A duplicate name is a failure too, because the second
line would otherwise win in silence.

**The module must fail closed.** Each of these is a failure, and none of them is
a skip:

- an absent file
- an absent key
- an unparsed line
- a duplicate name
- a name that the manifest does not hold

**The module must not log.** Every failure returns `undef`, and `error` holds
the reason. The caller decides how to report it. `Fugu::Sandbox` sets the same
precedent: it fails and never logs.

**A digest comparison needs no constant-time compare.** A manifest digest is
public data, and no secret enters the module.

## The interface contract

### new

`new(%args)` builds a verifier. The method resolves the command once, and it
runs no process.

| Argument  | Meaning                                                                                        |
| --------- | ---------------------------------------------------------------------------------------------- |
| `keys`    | An array reference of public key file paths. This argument is necessary and must not be empty. |
| `command` | The signify command, as a name or as an absolute path. The default comes from the search list. |

The order of `keys` is the trust order. A caller puts the current key first and
the next key second. `verify` returns the key that matched, so a caller learns
that the release moved to the next key.

`new` dies when `keys` is absent, when it is not an array reference, and when it
is empty. Each one is a programming error.

`new` must not die for an absent command. It sets `error` instead, and
`is_available` then returns 0.

### is_available

`is_available()` returns 1 when the module resolved an executable command. It
returns 0 otherwise. The method runs no process, and it never dies.

### command

`command()` returns the resolved command, or `undef`. An operator who installed
the wrong `signify` on Debian needs this answer, and a caller can put it in a
diagnostic.

### error

`error()` returns the reason of the most recent failure. It returns `undef`
after a success. Every public method clears the reason before it starts.

For a signature that no key verified, the string names the file. It then names
each key with the first line of its signify diagnostic:

```
/var/cache/SHA256: no key verified the signature:
    /etc/signify/openbsd-78-base.pub: signature verification failed;
    /etc/signify/openbsd-79-base.pub: can't open /etc/signify/openbsd-79-base.pub
```

A caller thus tells a wrong key from an absent key file.

### command_absent

`command_absent()` returns 1 when the most recent failure means that signify(1)
never ran. It covers a command that the search list did not resolve, and a
command that failed to execve(2). It returns 0 otherwise.

The two answers need a difference at the interface. An absent command is an
install problem, and a failed signature is an integrity problem. A caller that
cannot tell them apart must either ignore both or fail on both.
`Fugu::Control::Client->socket_absent` sets the same precedent.

### verify

`verify($file, $sigfile)` verifies one file against the key set. `$sigfile`
defaults to `"$file.sig"`, which is the default of signify(1) itself.

The method returns the public key file that verified the signature. It returns
`undef` on every failure.

The method works in this order:

1. It returns `undef` at once when `is_available` is 0. `command_absent`
   becomes 1.
2. It returns `undef` when `$file` is not a plain file, or when `$sigfile` is
   not a plain file. One check covers every key, and it names the missing path.
3. It runs signify(1) once for each key, in order, and it returns the first key
   that exits 0.
4. It returns `undef` with the collected reasons.

Each call builds this argument list:

```perl
	my @cmd = (
		$self->{command}, '-V', '-q',
		'-p', $key,
		'-x', $sigfile,
		'-m', $file,
	);
```

`-q` suppresses the success line, so the module reads the exit code and the
standard error only.

### verify_manifest

`verify_manifest(%args)` verifies a signed SHA256 manifest, and then verifies
the digest of each named file.

| Argument    | Meaning                                                                                           |
| ----------- | ------------------------------------------------------------------------------------------------- |
| `manifest`  | The path of the signed SHA256 file. This argument is necessary.                                   |
| `signature` | The path of the signature file. The default is `"$manifest.sig"`.                                 |
| `files`     | A hash reference. Each key is a name in the manifest, and each value is the local path to digest. |

`files` is necessary and must not be empty. The module must never choose which
file to check. A caller that names no file would get a pass that proves nothing.
An empty `files` is therefore a programming error, and the method dies.

The method returns the public key file that verified the manifest. It returns
`undef` on every failure.

The method works in this order:

1. It calls `verify($manifest, $signature)`. A failure returns `undef` at once.
   No file is digested before the manifest verifies.
2. It refuses a manifest above `MAX_MANIFEST_SIZE`, by the size on disk.
3. It reads the manifest with `Fugu::File->read`, and it parses it with
   `_parse_manifest`.
4. For each name in `files`, the manifest must hold the name. A name that the
   manifest does not hold is a failure.
5. It digests the local file with `_digest`. A file that does not open is a
   failure.
6. It compares the two digests, case-folded. A mismatch names the file, the
   expected digest and the computed digest.
7. It returns the key file from step 1.

This call verifies the FuguVM miniroot download:

```perl
	my $key = $sig->verify_manifest(
		manifest => "$cache/SHA256",
		files    => { 'miniroot78.img' => $tmp_path },
	);
```

The manifest name and the local path differ, and the hash reference carries that
difference. A caller therefore verifies a file before it moves the file into
place.

### The constants

| Constant            | Value | Reason                                                                                                                              |
| ------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `MAX_MANIFEST_SIZE` | 1 MiB | An OpenBSD SHA256 file holds tens of lines. A caller that names a disk image by mistake gets a clean failure, not a read of 500 MB. |
| `SIGNIFY_TIMEOUT`   | 30    | A command that a caller named can be the wrong program. The timeout bounds one call, and signify(1) needs milliseconds.             |

The timeout is a constant and not an argument. No consumer needs a second value,
and the repository must not keep an option that only a test sets.

### The private helpers

Each helper has one caller, and the `.pod` must not document any of them.

`_find_command($name)` returns an executable path, or `undef`. With a name that
holds a solidus it tests that path only. Without one it walks `$ENV{PATH}` over
the search list `signify-openbsd`, then `signify`.

`_run_signify($key, $sigfile, $file)` runs one signify(1) call through
`Fugu::Process->run`, with `timeout => SIGNIFY_TIMEOUT`. It returns the hash
reference that `run` returns.

`_parse_manifest($bytes)` returns a hash reference of name to lowercase hex
digest, or `undef`. It parses the OpenBSD `sha256(1)` line form:

```
SHA256 (miniroot78.img) = 4f2b...
```

It refuses an empty manifest, a line it cannot parse, a digest that is not 64
hexadecimal characters, and a duplicate name.

`_digest($path)` returns the lowercase hex SHA256 digest of the file, or
`undef`. It opens the file, sets `binmode`, and streams the bytes:

```perl
	my $sha = Digest::SHA->new(256);
	$sha->addfile($fh);
```

`addfile` reads in blocks, so a file set of 500 MB never enters memory whole.

### What the module must not hold

The module must have no `sign` method, and it must take no secret key path. The
`.pod` must state both facts, and a test must assert that
`Fugu::Signify->can('sign')` is false.

## Load contract

The module needs core Perl only. It loads three modules at compile time:

```perl
use Digest::SHA ();
use Fugu::File;
use Fugu::Process;
```

`Digest::SHA` is core Perl. `App::FuguVM::DiskCache` already loads it the same
way, at line 32: `use Digest::SHA ();`. `Fugu::File` and `Fugu::Process` are
`Fugu::` modules, and both need core Perl only.

The module adds no CPAN library, so the `cpanfile` needs no line.

signify(1) is an external command, and not a Perl library. OpenBSD base holds
it, so `deps/OpenBSD.txt` needs no line. `deps/Linux.txt` and `deps/Darwin.txt`
need one test line each, so CI runs the real verification path:

```
test pkg signify-openbsd
```

```
test pkg signify-osx
```

`scripts/deps` installs a Linux `pkg` line with `apt-get install -y`, and a
Darwin `pkg` line with `brew install`.

`t/fugu/coreperl.t` proves the load contract: it loads every module under
`lib/Fugu` with a pruned `@INC`. `t/protocol/boundary.t` proves that no `App::`
namespace and no unlisted `Protocol::` codec enters.

## Files

| File                   | Content                                                                           |
| ---------------------- | --------------------------------------------------------------------------------- |
| `lib/Fugu/Signify.pm`  | The module: seven public subs, four private helpers, and the two constants        |
| `lib/Fugu/Signify.pod` | The API sidecar: every public sub, the return values, the errors, and the caveats |
| `lib/Fugu.pod`         | One index entry, between `Fugu::Signal` and `Fugu::StateFile`                     |
| `t/fugu/signify.t`     | The unit test                                                                     |
| `README.md`            | The capability list of the intro paragraph gains signature verification           |
| `deps/Linux.txt`       | `test pkg signify-openbsd`                                                        |
| `deps/Darwin.txt`      | `test pkg signify-osx`                                                            |
| `deps/OpenBSD.txt`     | No change. signify(1) is in base                                                  |
| `cpanfile`             | No change. The module adds no CPAN library                                        |
| `INSTALL.md`           | No change. The file names no external command today                               |

The `Fugu.pod` entry reads:

```
=item L<Fugu::Signify> - verify a signify(1) signature and a SHA256 manifest
```

The index is in ASCII order, so the entry sits after `Fugu::Signal` and before
`Fugu::StateFile`.

The `.pod` needs a CAVEATS section with four facts:

- The module cannot sign.
- The command name differs by platform.
- A caller under taint mode must pass an absolute `command`.
- A caller under pledge(2) needs `rpath` and `proc exec`.

## Tests

`t/fugu/signify.t` uses `Test::More` and `done_testing()`. It builds every
fixture under a `File::Temp` directory.

The test generates its own key material. signify(1) creates a throwaway key pair
with `-G`, and it signs a fixture with `-S`. The module never signs, so the test
drives the command directly for the setup. This gives the test a real signature,
a real second key, and a real wrong-key case.

These subtests need no signify(1), and they must always run:

- `new` dies for an absent `keys`, for a scalar `keys`, and for an empty `keys`.
- `new` with `command => '/nonexistent/signify'` returns an object.
  `is_available` returns 0, `command` returns `undef`, and `error` names the
  reason.
- `verify` on that object returns `undef`, `command_absent` returns 1, and the
  call does not die.
- `verify_manifest` on that object returns `undef` and does not die.
- `verify_manifest` dies for an absent `manifest`, and for an empty `files`.
- `_parse_manifest` reads a manifest of three lines into three pairs.
- `_parse_manifest` returns `undef` for an empty manifest.
- `_parse_manifest` returns `undef` for a line it cannot parse.
- `_parse_manifest` returns `undef` for a digest that is not 64 hex characters.
- `_parse_manifest` returns `undef` for a duplicate name.
- `_parse_manifest` folds an upper-case digest to lower case.
- `_digest` returns the known SHA256 digest of a fixed string.
- `_digest` returns `undef` for a file that does not open.
- `_find_command` returns `undef` for a name that no `PATH` entry holds.
- `_find_command` returns the path for a name in a temporary `PATH` entry.
- `MAX_MANIFEST_SIZE` and `SIGNIFY_TIMEOUT` hold the documented values.
- `Fugu::Signify->can('sign')` is false.

These subtests need signify(1), and each one calls
`plan skip_all => 'signify(1) not available'` when the command is absent:

- `verify` returns the key path for a good signature.
- `verify` returns `undef` for a tampered message, and `error` names the file.
- `verify` returns `undef` for a wrong key, and `command_absent` returns 0.
- `verify` with a key set of two returns the second key when the second key
  signed the file.
- `verify` returns `undef` for an absent message file, and the reason names the
  path.
- `verify` returns `undef` for an absent signature file.
- `verify` uses `"$file.sig"` when the caller passes no signature path.
- `verify_manifest` returns the key path for a good manifest and a good file.
- `verify_manifest` returns `undef` for a file whose digest does not match, and
  `error` names that file.
- `verify_manifest` returns `undef` for a name that the manifest does not hold.
- `verify_manifest` returns `undef` for a local file that does not open.
- `verify_manifest` returns `undef` for a manifest above `MAX_MANIFEST_SIZE`.
- `verify_manifest` returns `undef` for a manifest with a broken signature, and
  it digests no file.
- `verify_manifest` accepts a manifest name that differs from the local path.

One path the unit test cannot cover: a real OpenBSD `SHA256` file and its
release key. FuguVM proves that path against a live mirror, in the test of its
plan 005. The plan states the limit, because a reader must not believe that
`t/fugu/signify.t` verified an OpenBSD release.

## Acceptance

- `make check` passes: `make lint`, `make test`, `make tidy`, and
  `make spec-coverage`.
- `t/fugu/signify.t` passes, and it skips the signify(1) subtests when the
  command is absent.
- `t/fugu/coreperl.t` passes: the module loads with core Perl only.
- `t/protocol/boundary.t` passes: the module loads no `App::` namespace.
- `t/scripts/symbols.t` passes: the test names each private helper and each
  constant, and `lib/` or the test names every public sub.
- `make prettier` passes for `README.md` and for this plan.
- The `.pod` documents `new`, `is_available`, `command`, `error`,
  `command_absent`, `verify` and `verify_manifest`. It documents no private
  helper.
- The `.pod` CAVEATS holds the four facts of the Files section.
- `make deps-test` installs the command on Linux and on Darwin, and the signify
  subtests then run instead of skipping.
- FuguVM still passes against a build of this branch:
  `cpanm --local-lib=local ../Fugu/build/Fugu-*.tar.gz`, then `make check` in
  FuguVM. The module is new, so no FuguVM test changes.

## Open questions

1. **The Darwin package name.** The plan proposes `signify-osx`, which installs
   the command as `signify`. `brew info signify-osx` must confirm the name
   before the line lands in `deps/Darwin.txt`. A wrong name breaks
   `make deps-test` on Darwin.
2. **The search order guesses.** On Debian the name `signify` can belong to an
   unrelated program. The plan therefore tries `signify-openbsd` first. A
   reviewer who wants no guess can make `command` a necessary argument. The plan
   keeps the search list, because a laptop and an OpenBSD host must work with no
   configuration.
3. **No consumer sets `command` today.** FuguVM plan 005 can rely on the search
   list. The argument stays for two reasons. A caller under taint mode has no
   other way to reach execve(2), and an operator can hold signify(1) outside
   `PATH`.
4. **The key set has no expiry.** signify(1) carries no validity period, so a
   caller that keeps a retired key accepts it forever. An expiry needs a date
   policy, and policy does not belong in Fugu. The consumer owns the key set.
5. **The `-t keytype` flag.** signify(1) can check a key type token in the
   signature comment. No consumer needs it, so the argument list holds no `-t`.
6. **Who holds the OpenBSD release keys on a Linux host.** OpenBSD keeps them
   under `/etc/signify`, and a Linux host and a Darwin host hold no such tree.
   FuguVM plan 005 must decide where the keys come from. This module takes a
   path list and answers no key-distribution question.
