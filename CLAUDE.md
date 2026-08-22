@README.md

## Critical: writing standard

Write all output and all artifacts in ASD-STE100 Simplified Technical English.
This rule applies to documentation, specifications, code comments, commit
messages, pull requests, and chat replies.

- Use the active voice and the approved words.
- Write one instruction in each sentence.
- Keep each instruction shorter than 20 words.
- Keep each descriptive sentence shorter than 25 words.
- Use "must" for a requirement, "must not" for a prohibition, and "can" for a
  capability.
- Do not change technical names, commands, or code examples.

`make ste-lint` rejects banned words and patterns. `make check` runs it.

## The specification is a living document

The specification in [`spec/`](spec/index.md) states what the project is and
why. [spec/index.md](spec/index.md) is the entry point. Read
[spec/DECISIONS.md](spec/DECISIONS.md) before you make a plan. A plan must not
go against a decision.

The specification must agree with the project at all times. Apply these rules:

- When your change alters a design, an interface, or a procedure, update the
  specification in the same change.
- When the specification is wrong or not complete, correct the specification. Do
  not work around it, and do not let code and specification drift apart.
- When your change goes against a decision, stop. Propose a change to
  [spec/DECISIONS.md](spec/DECISIONS.md) and get human approval first.
- Write each update so that it describes the current target design only. Do not
  write an amendment, and do not refer to an earlier state.
- When your change implements a unit, or a part of a unit, set the state of the
  unit in [spec/STATUS.md](spec/STATUS.md) in the same change.

`make spec-check` validates the specification. `make check` runs it.

## Plans are transient

The specification states what and why. A plan in `plans/` states how and when
one change lands.

- A plan merges on its own, before the implementation starts.
- The pull request that implements a plan deletes the plan directory in the same
  change. After that, the specification and the code are the reference.
- A merged plan must not stay behind. `make spec-check` fails a plan that cites
  a `done` unit.

The full rules are in [plans/CLAUDE.md](plans/CLAUDE.md).

## Review

A panel of sub-agents reviews every implementation change before it merges. Each
panel member gets the same review prompt, and works alone. A finding that a
majority of the panel reports is a quorum finding. Resolve each quorum finding
before the merge. The procedure is in
[.claude/skills/review-panel/SKILL.md](.claude/skills/review-panel/SKILL.md).

## Workflow

- Run `make check` before each commit. It must pass.
- Use Conventional Commits: `<type>(<scope>): <description>`, with the types
  `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, and
  `chore`. The README names the scopes of this repository.
- Group unrelated changes into separate commits.

## Documentation

- Every fact lives in exactly one place. Everything else points to it.
- The README holds the identity of the repository. `spec/` holds the design. A
  directory `CLAUDE.md` holds the rules of that directory.
- No `README.md` exists outside the repository root.
- When a change alters behavior, options, or configuration, update the
  documentation in the same change.

## Scratch space

- Use `explore/` (gitignored) for scratch scripts and experiments, never `/tmp`.
- Write audit findings to `SCRATCHPAD-<N>.md` files (gitignored).
