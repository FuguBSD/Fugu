<!--
The org pack of FuguBSD/Tooling owns this file. Do not edit a synced
copy. Edit the canonical copy in FuguBSD/Tooling.
-->

@README.md

## Critical: writing standard

Write all output and all artifacts in ASD-STE100 Simplified Technical English:
documentation, specifications, code comments, commit messages, pull requests,
and chat replies. `make ste-lint` rejects banned words and patterns.

- Use the active voice and the approved words.
- Write one instruction in each sentence, shorter than 20 words.
- Keep each descriptive sentence shorter than 25 words.
- Use "must" for a requirement, "must not" for a prohibition, and "can" for a
  capability.
- Do not change technical names, commands, or code examples.

## Critical: the specification

The specification in [spec/](spec/index.md) is the design. The code and the
specification must agree in every change.

- Read [spec/DECISIONS.md](spec/DECISIONS.md) before you make a plan.
- When your change alters a design, an interface, or a procedure, update the
  specification in the same change.
- When your change implements a unit, or a part of one, set the unit state in
  [spec/STATUS.md](spec/STATUS.md) in the same change.
- When the specification is wrong, correct it. Do not work around it.
- When your change goes against a decision, stop and get human approval first.

The format rules are in [spec/CLAUDE.md](spec/CLAUDE.md).

## Plans

A plan in `plans/` states how one change lands. A plan merges first, and the
implementation deletes it. The rules are in [plans/CLAUDE.md](plans/CLAUDE.md).

## Workflow

- Run `make check` before each commit. It must pass.
- Write Conventional Commits: `<type>(<scope>): <description>`. The types are
  `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, and
  `chore`. The README names the scopes.
- Group unrelated changes into separate commits.
- Merge a patch-level change with [merge-it](.claude/skills/merge-it/SKILL.md).
- Merge a minor-level or major-level change with
  [pull-it](.claude/skills/pull-it/SKILL.md). It runs the
  [review panel](.claude/skills/review-panel/SKILL.md).

## Documentation

- Every fact lives in exactly one place. Everything else points to it.
- The README holds the identity, `spec/` holds the design, and a directory
  `CLAUDE.md` holds the rules of that directory.
- No `README.md` exists outside the repository root.
- When your change alters behavior, options, or configuration, update the
  documentation in the same change.

## Scratch space

- Put scratch scripts and experiments in `explore/` (gitignored), never in
  `/tmp`.
- Put audit findings in `SCRATCHPAD-<N>.md` files (gitignored).
