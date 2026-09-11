<!--
The perl pack of FuguBSD/Tooling owns this file. Do not edit a synced
copy. Edit the canonical copy in FuguBSD/Tooling.
-->

# lib/

Applies when working on Perl code in this repository.

## Coding style

OpenBSD style(9): 8-character tabs, continuation lines indent 4 spaces.
`make format` and `make lint` enforce the format — run `make format-fix` rather
than hand-formatting. `.perlcriticrc` deliberately relaxes many rules to match
OpenBSD style; do not "fix" code toward generic Perl::Critic defaults.

Rules the tools cannot enforce:

- Start each file with the version pragma of the source floor. The README names
  that floor. `use v5.36` turns on strict, warnings, say, and signatures. A
  v5.34 floor needs four lines: `use v5.34`, `use warnings`,
  `use experimental 'signatures'`, and
  `no feature qw(indirect multidimensional bareword_filehandles)`. A bootstrap
  Perl script takes v5.34 always, and `SYNC-BOOTSTRAP-1` names each one. It runs
  before any install, and macOS ships perl 5.34. A file that a Tooling pack owns
  keeps the pragma of its canonical copy. A consumer cannot edit that copy.
  `scripts/dist`, `t/ci/local.t`, and `t/ci/workflows.t` hold `use v5.36`. A
  consumer with a v5.34 source floor must run `make dist` and `make check` on a
  newer perl.
- Keep the source floor apart from the `dist.perl` key of `.toolingrc`. That key
  names the floor that the dist build stamps into a distribution, and the
  default is `5.036`. A repository with a lower source floor can set the key to
  the same value. No gate holds the two floors equal. The key must not go below
  the source floor. A lower value lets a perl below the source floor install the
  distribution. That perl then refuses to run the code.
- Object-oriented style with signatures; the object is `$self`; internal methods
  carry a `_` prefix; do not name unused parameters: `sub foo($, $) { }`.
- Function brace on its own line, control-structure brace on the same line:

```perl
sub method($self, $param)
{
	if ($condition) {
		...
	}
	return $result;
}
```

- Explicit `return`, except for no-return or constant methods. Omit parens on
  zero-argument method calls: `$object->width`.
- Inheritance via `our @ISA`, not `use parent`. No multiple inheritance.
  Multiple related packages per file are fine. Constants via `use constant`.
- A new file starts with the `# ex:ts=8 sw=4:` modeline and the ISC copyright
  header — copy them from a file in `lib/`.
- `Class->new`, never indirect object notation. Code refs always with
  parentheses, except delegation. No old-style prototypes unless creating
  syntax.
- Prefer simple string operations over a regex where they suffice. Use
  `wantarray()` only as an optimization, never to change semantics.

## Error handling and security

- Return `undef` (bare `return`) for a recoverable error. `die` for a
  programming error. Never use `eval` for flow control.
- Never ignore the return value of a system call:
  `open my $fh, '<', $file or do { warn "..."; return; };`
- No threads — multiplex with `IO::Select`.
- Take randomness from `/dev/urandom`. Design for pledge(2) and unveil(2). Fail
  closed. Never trust external input.

## Modules and documentation

- Every module has a `.pod` sidecar — never inline POD.
- A new module needs its `.pod` sidecar and a test.

## Testing

- Unit tests use `Test::More` with `done_testing()`. A test skips gracefully
  when a dependency is unavailable (`plan skip_all => ...`). Mirror an existing
  test when adding one.
