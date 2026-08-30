<!--
The org pack of FuguBSD/Tooling owns this file. Do not edit a synced
copy. Edit the canonical copy in FuguBSD/Tooling.
-->

# plans/

Applies when working on files under `plans/`.

## Transient

- A plan merges on its own, before the implementation starts.
- The pull request that implements a plan deletes the plan directory in the same
  change.
- When a part of a plan lands, trim the citations of the plan in the same
  change, or delete the plan. `make spec-check` fails a plan that cites a `done`
  unit under `Implements:`.

## Location

- A plan lives in the repository that implements it. It must not describe work
  that another repository implements. The citation forms live in
  [spec/CLAUDE.md](../spec/CLAUDE.md).

## Numbering

The path is `plans/<NNN>-<slug>/plan.md`, and the first line is
`# <NNN> — <subject>`. A number is never reused, also after the deletion of its
plan. To find the next number, run:

```sh
git log --diff-filter=A --name-only --format= -- plans/ | sort -u
```

## Shape

- A plan cites each unit that it implements, per the plan contract in
  [spec/index.md](../spec/index.md). Every cited ID must exist.
- A plan holds a Status section: what can land now, what waits, and on what.
