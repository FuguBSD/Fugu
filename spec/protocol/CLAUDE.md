# protocol/

Applies when working on files under `spec/protocol/`.

## Purpose

The files here are the curated protocol references that Fugu implements against,
and the normative source that the conformance tier cites:

- `MDNS.md` — index and overview; the entry point into the `MDNS-*.md` topic
  files
- `MDNS-Imsg.md` — the imsg(3) frame that `Protocol::Imsg` encodes and
  `Fugu::Imsg` transports
- `MDNS-Control.md` — the OpenBSD mdnsd control protocol that `Fugu::Mdnsd`
  speaks over the control socket

These documents are curated reference material, not the living specification.
The living specification lives one level up, in `spec/`.

## Writing changes

Edit the documents in place — deepen a section, correct an error, add a missing
case — and keep every claim traceable: cite the upstream source file, and the
line where it helps, as the surrounding text does. Local clones of the upstream
repositories belong in the gitignored `external/`.

The structure carries the citations:

- Numbered `##`/`###` headings are the citation anchors. `make spec-coverage`
  parses them, and it fails on a test citation that points at a section that
  does not exist. When you renumber or resequence sections, update the citations
  in the same change.
- One normative topic file maps to one conformance test file
  (`spec/protocol/MDNS-Imsg.md` ↔ `t/conformance/mdns-imsg.t`). A new topic file
  needs its test file. See `t/CLAUDE.md`.
- Tables are catalogs that the tests loop over. Unnumbered rows are cited as
  `§<section>/<row>`, so row labels are anchors too.
- Tests replay the wire examples byte for byte. Correct an example only against
  a source, never to match the code.
