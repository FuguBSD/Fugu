# lib/

Applies when working on Perl code in this repository.

## Coding style

OpenBSD style(9): 8-character tabs, continuation lines indent 4 spaces.
`make tidy` and `make lint` enforce the format — run `make tidy-fix` rather than
hand-formatting. `.perlcriticrc` deliberately relaxes many rules to match
OpenBSD style; do not "fix" code toward generic Perl::Critic defaults.

Rules the tools cannot enforce:

- Always `use v5.36` (strict, warnings, say, signatures). The one exception is a
  bootstrap script such as `scripts/deps`: it runs before anything is installed,
  and macOS ships perl 5.34.
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
- Fail cleanly: diagnose invalid input in a human-readable message, never a
  stack trace. Leave no partial file, orphaned process, or corrupt state behind.
  Make repeatable operations truly idempotent.
- Take randomness from `/dev/urandom`. Design for pledge(2) and unveil(2). Fail
  closed. Never trust external input.

## Simplicity

- Delete an old code path outright. Never keep an alias, a bridge, or a
  migration.
- Do not keep test-only API. Delete a sub or an option that only tests use,
  together with its test.
- Validate each input once, at its boundary. Do not check the same invariant
  again downstream.

## Modules and documentation

- Every module has a `.pod` sidecar — never inline POD.
- A new module needs its `.pod` sidecar and a test.

## Testing

- Unit tests use `Test::More` with `done_testing()`. A test skips gracefully
  when a dependency is unavailable (`plan skip_all => ...`). Mirror an existing
  test when adding one.
- Be resilient to timing variations.
- Every feature needs tests.
