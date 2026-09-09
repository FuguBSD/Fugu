<!--
The org pack of FuguBSD/Tooling owns this file. Do not edit a synced
copy. Edit the canonical copy in FuguBSD/Tooling.
-->

@README.md

## Critical: the Unix philosophy

Simplicity is the design principle of every artifact: code, tool, document,
process, and plan.

- Make each tool, module, and script do one thing, and do it well.
- Compose small parts through plain interfaces: text in, text out, and an exit
  code.
- Choose the design with the fewest parts. Add a part for a present need only.
- Keep a tool silent on success, and exact on failure.
- Prefer a removal to an addition. Delete what no one needs.

## Critical: writing standard

Write every artifact and every reply in ASD-STE100 Simplified Technical English.
`make ste-lint` enforces it.

- Use the active voice and the approved words.
- Write one instruction in each sentence, shorter than 20 words.
- Keep each descriptive sentence shorter than 25 words.
- Use "must" for a requirement, "must not" for a prohibition, and "can" for a
  capability.
- Do not change technical names, commands, or code examples.

## Critical: the specification

The specification in [spec/](spec/index.md) states what the system does, and
why. The code and the specification must agree in every change.

- Read [spec/DECISIONS.md](spec/DECISIONS.md) before you plan.
- When a change alters a design, an interface, or a procedure, update the
  specification in the same change.
- When a change implements a unit, or a part of one, set its state in
  [spec/STATUS.md](spec/STATUS.md) in the same change.
- When the specification is wrong, correct it. Do not work around it.
- When a change goes against a decision, stop and get human approval first.
- A design document holds no step and no schedule. A step belongs in a plan, and
  a schedule belongs in a record.
- The format rules are in [spec/CLAUDE.md](spec/CLAUDE.md).

## Plans

A plan in `plans/` states how one change lands, and when. The specification
holds the design, and the plan holds the steps.

- A plan holds the steps, their order, and their state: what lands now, what
  waits, and on what.
- A plan cites each unit that it implements, extends, or defers. The design
  stays in the specification.
- A plan merges first, on its own. The implementation deletes it in the same
  change.
- The format rules are in [plans/CLAUDE.md](plans/CLAUDE.md).

## Workflow

- Run `make check` before each commit. It must pass.
- Write Conventional Commits: `<type>(<scope>): <description>`. The types are
  `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, and
  `chore`.
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
- When a change alters behavior, options, or configuration, update the
  documentation in the same change.

## Scratch space

- Put scratch scripts and experiments in `scratch/` (gitignored), never in
  `/tmp`.
- Put audit findings in `SCRATCHPAD-<N>.md` files (gitignored).
