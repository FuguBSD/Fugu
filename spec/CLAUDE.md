<!--
The org pack of FuguBSD/Tooling owns this file. Do not edit a synced
copy. Edit the canonical copy in FuguBSD/Tooling.
-->

# spec/

Applies when working on files under `spec/`. [index.md](index.md) is the entry
point: it holds the plan contract, the ID conventions, and the document tables.
[DECISIONS.md](DECISIONS.md) holds the decisions.

## Format

- One document specifies one area of work.
- Each design document describes the target design in the current state only: no
  amendment, and no reference to an earlier state.
- [ROADMAP.md](ROADMAP.md), [STATUS.md](STATUS.md), and `LEARNING.md` are
  records, not design documents. Only a record says when work occurs, and only a
  record refers to an earlier state.
- `LEARNING.md` holds the learning of each rehearsal. A repository adds it only
  when it runs campaigns.
- A rule item can join tightly coupled requirements on one object with "and
  must".

## The ID overlay

A unit is one implementable design element. An invisible HTML anchor marks each
unit, and the unit ID is the anchor in upper case:

```markdown
<a id="doc-example"></a>

## Example functions

- **DOC-EXAMPLE-1** — The example function must …
```

- The anchor starts with the document code, in lower case, followed by a hyphen.
  [index.md](index.md) holds the codes.
- A unit runs from its anchor to the next unit anchor or heading.
- A rule ID names one requirement inside a unit, as a bold-lead list item.
- Rule numbers only append: never renumber, and never reuse a number.
- An ID must not change. To retire a unit: delete its anchor and its register
  row, and add the ID to the "Retired IDs" table of the register.
- A plan cites units and rules: `Implements: DOC-EXAMPLE without DOC-EXAMPLE-1`,
  `Extends: DOC-DONE`, and `Defers: DOC-OTHER`. A citation starts a paragraph or
  a list item, and a second citation in the same block starts a sentence. A
  citation ends at its first period, and it must hold text after the verb. Code,
  bold, and italic marks around a verb do not change it. `Extends:` names a
  `done` unit whose rules change in the implementation of the plan: a new rule,
  or a changed rule text. The implementation lands the change with its code, so
  the unit stays `done`. `Extends:` takes a unit only: no rule ID, and no
  `without`. A plan cites a unit under one verb only.
- A citation of a unit of a sibling repository is a prose token, for example
  `FuguOracle OPS-GET-4`: never a link, and never a plan name.

## STATUS.md, the implementation register

One row per unit: a state, a "Done by" phase, and a note.

- The states are `open`, `partial`, `done`, and `n-a`.
- A `partial` note names each absent part.
- A `done` note links the code or the tests.
- The "Done by" value names a phase of [ROADMAP.md](ROADMAP.md), or "—" when no
  phase applies.

## Checks

`make spec-check` validates this specification and the plans, and CI runs the
drift gate on each pull request. The rules of the check live at
<https://github.com/FuguBSD/Tooling/blob/main/spec/spec-check.md>.
