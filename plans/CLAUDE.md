# plans/

Applies when working on files under `plans/`.

## One sequence across the FuguBSD repositories

A plan lives in the repository that implements it. `Fugu::` module work is a
Fugu plan. `fuguvm` tool work is a FuguVM plan. Harness work is a FuguTTX plan.

The plan numbers are one sequence across those repositories, and no number
repeats. A new plan takes the next free number in the family, not the next free
number in its own repository. Therefore a citation of "plan 009" names one plan,
and a reader needs no repository name to find it.

A number must not change after the plan lands. A plan that a repository drops
leaves its number retired.

## The shape of a plan

The path is `plans/<NNN>-<slug>/plan.md`, and the first line is
`# <NNN> — <subject>`.

A plan cites the unit IDs and the rule IDs that it serves, in a consumers table.
Every ID must exist. A plan names each method that it adds, and it states the
load contract of the module. A plan that adds API with no caller of record says
so in its Status section, and it waits for that caller.

## Writing

ASD-STE100 Simplified Technical English, as the repository root states.
