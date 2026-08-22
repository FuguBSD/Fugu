# CLAUDE.md

This directory holds the specification. [index.md](index.md) is the entry point.
It holds the plan contract, the ID conventions, and the document tables.
[DECISIONS.md](DECISIONS.md) holds the decisions. A plan must not go against a
decision.

## Format

- One document specifies one area of work.
- All text complies with ASD-STE100 Simplified Technical English: short
  sentences, the active voice, one instruction per sentence, "must" for a
  requirement, "must not" for a prohibition, "can" for a capability.
- A rule item can join tightly coupled requirements on one object with "and
  must". Each sentence stays short and active.
- Each document describes the target design in the current state only. Do not
  write an amendment, and do not refer to an earlier state.
- Only [ROADMAP.md](ROADMAP.md) and [STATUS.md](STATUS.md) say when work occurs.

## The ID overlay

A unit is one implementable design element. An invisible HTML anchor marks each
unit, and the unit ID is the anchor in upper case:

```markdown
<a id="doc-example"></a>

## Example functions

- **DOC-EXAMPLE-1** — The example function must …
```

- The anchor of a unit must start with the code of its document, in lower case,
  followed by a hyphen. The document codes are in [index.md](index.md).
- A unit extends from its anchor to the next unit anchor or heading, whichever
  comes first.
- A rule ID names one requirement inside a unit, as a bold-lead list item, as
  the example above shows. Rule numbers only append: never renumber, and never
  reuse a number.
- A plan cites units and rules: `Implements: DOC-EXAMPLE without DOC-EXAMPLE-1`
  and `Defers: DOC-OTHER`.
- An ID must not change. To retire a unit: delete its anchor and its register
  row, and add the ID to the "Retired IDs" table of the register.
- A citation of a unit of a sibling repository is a prose token with the
  repository name in front, for example `FuguOracle OPS-GET-4`. It is never a
  link, and it never names a plan.

## STATUS.md, the implementation register

[STATUS.md](STATUS.md) is the only home of implementation state: one row per
unit, with a state (`open`, `partial`, `done`, `n-a`), a "Done by" phase, and a
note. When your change implements a unit, or a part of a unit, set the state of
the unit in the register in the same change. A `partial` note names each absent
part. A `done` note links the code or the tests. The "Done by" value names a
phase of [ROADMAP.md](ROADMAP.md), or "—" when no phase applies.

## Checks

`make spec-check` validates the links, the anchors, the register, the rule
definitions, the citations, the schedule lint, and the plans. A plan that cites
a `done` unit under `Implements:` fails the check: delete or trim the plan in
the change that sets the state. On a pull request, CI adds a drift gate: a
change to a document with a `partial` or `done` unit must also change STATUS.md
or a mapped code root.
