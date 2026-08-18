# spec/

Applies when working on files under `spec/`.

## Purpose

`spec/*.md` are the curated protocol references Fugu implements against, and the
normative source the conformance tier cites:

- `MDNS.md` — index and overview; entry point into the `MDNS-*.md` topic files
- `MDNS-Imsg.md` — the imsg(3) frame that `Protocol::Imsg` encodes and
  `Fugu::Imsg` transports
- `MDNS-Control.md` — the OpenBSD mdnsd control protocol that `Fugu::Mdnsd`
  speaks over the control socket

## Writing changes

These are hand-maintained documents. Edit them in place — deepen a section, fix
an error, add a missing case — and keep every claim traceable: cite the upstream
source file (and line, where it helps) a value or behavior comes from, as the
surrounding text does. Local clones of those upstream repositories, if you keep
any, belong in the gitignored `external/`.

Structure is load-bearing, not cosmetic:

- Numbered `##`/`###` headings are the citation anchors. `make spec-coverage`
  parses them and fails on any test citation pointing at a section that no
  longer exists, so renumbering or resequencing sections breaks tests in
  `t/conformance/` — update the citations in the same change.
- One normative topic file maps to one conformance test file
  (`spec/MDNS-Imsg.md` ↔ `t/conformance/mdns-imsg.t`); adding a topic file means
  adding its test file. See `t/CLAUDE.md`.
- Tables are catalogs the tests loop over; unnumbered rows are cited as
  `§<section>/<row>`, so row labels are anchors too.
- Wire examples are replayed byte-exactly by tests. Correct them only against a
  source, never to match the code.
