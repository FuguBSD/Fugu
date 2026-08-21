# plans/

Applies when working on files under `plans/`.

## A plan lives where the work lands

A plan lives in the repository that implements it. `Fugu::` module work is a
Fugu plan. `fuguvm` tool work is a FuguVM plan. Harness work is a FuguTTX plan.
A plan must not describe work that another repository implements.

Each repository numbers its own plans, from `001`. A citation across a
repository boundary therefore carries the repository name, for example "Fugu
plan 003". Never write a bare "plan 003" for a plan of an other repository.

A number must not change after the plan lands. A plan that the repository drops
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
