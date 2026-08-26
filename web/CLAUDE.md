<!--
The web pack of FuguBSD/Tooling owns this file. Do not edit a synced
copy. Edit the canonical copy in FuguBSD/Tooling.
-->

# Shared website instructions

This directory holds the website sources. fuguweb(1) reads `.fuguwebrc` and
renders the sources that it names: the `*.body.html` fragments, and the mdoc,
POD, and Markdown sources of the repository. On a push to `main`, the
`publish.yml` workflow of the repository calls the shared `web-publish.yml`
workflow, which builds the site and deploys it to GitHub Pages.

## The visitor

- Write each page for the visitor, not for the maintainer.
- A visitor decides in one minute: what the project does, if it fits the need,
  and where to start.
- The first paragraph of the front page must state what the project does and
  which problem it solves.
- The front page must point the visitor to the source repository and the
  specification. Point to the manuals when they exist.

## Content

- Keep each page short. A page holds the purpose, the design properties that set
  the project apart, and the pointers.
- The manuals and the specification hold the details. Link to them, and do not
  copy them.
- State a distinctive property as a fact that the specification or the manuals
  support.
- Do not compare the project with a named product, and do not use a superlative.
- Keep the page consistent with the README. When both state the same fact, use
  the same words.

## The ecosystem

- Name a sibling project only when a dependency or an interface connects the two
  projects, and link to its website.
- The footer connects each site to the organization. Every sibling website shows
  the same footer: the organization link, the copyright, and the license.

## The footer

- `web/footer.body.html` is a synced file of the `web` pack. Do not edit it in a
  consumer repository.
- The footer is the only legal text of the site. The repository LICENSE governs
  the content, as it governs the code.

## Checks

- `fuguweb build --out web/build` renders the site, and
  `fuguweb check --out web/build` validates it.
- Do not track `web/build/`. The org pack `.gitignore` ignores it, and the
  publish workflow builds the site fresh.
