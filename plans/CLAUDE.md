# plans/

Applies when working on files under `plans/`.

## A plan is transient

The specification states what the project is and why. A plan states how and when
one change lands.

- A plan merges on its own, before the implementation starts.
- The pull request that implements a plan deletes the plan directory in the same
  change.
- After the deletion, the specification and the code are the only reference.
- `make spec-check` fails a plan that cites a `done` unit under `Implements:`.
  When a part of a plan lands, trim the citations of the plan in the same
  change, or delete the plan.

## A plan lives where the work lands

A plan lives in the repository that implements it. A plan must not describe work
that another repository implements. A citation across a repository boundary
names the repository and the unit, for example `FuguOracle OPS-GET-4`. It must
not name a plan.

## Numbering

The path is `plans/<NNN>-<slug>/plan.md`, and the first line is
`# <NNN> — <subject>`. A number is never reused, also after the deletion of its
plan. Git history holds the used numbers. To find the next number, run:

```sh
git log --diff-filter=A --name-only --format= -- plans/ | sort -u
```

## The shape of a plan

- A plan cites each unit that it implements, per the plan contract in
  [spec/index.md](../spec/index.md).
- Every cited ID must exist in the specification.
- A plan holds a Status section. The section states what can land now, what
  waits, and on what.

## Writing

ASD-STE100 Simplified Technical English, as the repository root states.
