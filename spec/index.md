# Fugu specification

Fugu is a library of generic OpenBSD-style daemon utilities for Perl: core Perl
v5.36, no runtime dependencies. The repository also ships `Protocol::Imsg`, the
imsg(3) frame codec. OpenBSD is the production platform; Linux and Darwin serve
development and CI.

This document is the entry point of the specification. It holds the plan
contract, the ID conventions, and the document tables. The curated protocol
references live in [protocol/](protocol/MDNS.md); the conformance tier cites
them by section.

## Plan contract

- Read [DECISIONS.md](DECISIONS.md) before you make a plan.
- A plan must not go against a decision. To go against a decision, propose a
  change to [DECISIONS.md](DECISIONS.md) and get human approval first.
- A plan must cite each unit that it implements, for example
  `Implements: LIB-SSH`.
- A plan can exclude a rule from a cited unit with `without`, for example
  `Implements: LIB-SSH without LIB-SSH-1`.
- A plan must cite each unit that it touches but defers, for example
  `Defers: LIB-IMSG`.
- The change that implements a unit, or a part of a unit, must set the state of
  the unit in [STATUS.md](STATUS.md) in the same change.

<a id="conventions"></a>

## Conventions

A unit is one implementable design element. An invisible HTML anchor marks each
unit, and the unit ID is the anchor in upper case:

```markdown
<a id="lib-ssh"></a>

## Fugu::SSH

- **LIB-SSH-1** — The client must …
```

- The anchor of a unit must start with the code of its document, in lower case,
  followed by a hyphen.
- A unit extends from its anchor to the next unit anchor or heading, whichever
  comes first.
- A rule ID names one requirement inside a unit. A rule is a bold-lead list
  item: the bold rule ID, one em dash, then the requirement text, as the example
  above shows.
- Rule numbers only append: never renumber a rule, and never reuse a number.
- An ID must not change. To retire a unit: delete its anchor and its register
  row, and add the ID to the "Retired IDs" table of [STATUS.md](STATUS.md).
- Each document describes the target design in the current state only. Only
  [ROADMAP.md](ROADMAP.md) and [STATUS.md](STATUS.md) say when work occurs.
- A citation of a unit of a sibling repository is a prose token with the
  repository name in front, for example FuguTTX HRN-PERL. It is never a link,
  and it never names a plan.

## Specification documents

Each document specifies one area of work. The code of a document prefixes the
IDs of its units.

| Code | Document                           | Area                                       |
| ---- | ---------------------------------- | ------------------------------------------ |
| ARC  | [architecture.md](architecture.md) | Namespaces, boundaries, and load contract  |
| LIB  | [library.md](library.md)           | The modules and their concerns             |
| REL  | [release.md](release.md)           | Versioning, the dist, and the release flow |

## Governance documents

These documents carry no units.

| Document                     | Role                                                  |
| ---------------------------- | ----------------------------------------------------- |
| [DECISIONS.md](DECISIONS.md) | The decisions. A plan must not go against a decision. |
| [ROADMAP.md](ROADMAP.md)     | The schedule of the work.                             |
| [STATUS.md](STATUS.md)       | The implementation register.                          |
