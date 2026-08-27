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
- `LEARNING.md` holds the learning of each campaign. A repository adds it only
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
- A unit extends from its anchor to the next unit anchor or heading.
- A rule ID names one requirement inside a unit, as a bold-lead list item.
- Rule numbers only append: never renumber, and never reuse a number.
- An ID must not change. To retire a unit: delete its anchor and its register
  row, and add the ID to the "Retired IDs" table of the register.
- A plan cites units and rules: `Implements: DOC-EXAMPLE without DOC-EXAMPLE-1`
  and `Defers: DOC-OTHER`.
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

`make spec-check` validates the links, the anchors, the register, the rules, the
citations, the schedule lint, and the plans. On a pull request, CI adds a drift
gate: a change to a document with a `partial` or `done` unit must also change
STATUS.md or a mapped code root.
