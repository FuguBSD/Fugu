---
name: review-panel
description:
  Review the change set of this branch with a panel of independent sub-agents
  that share one review prompt. Use before a minor-level or major-level merge,
  or when the user asks for a panel review.
---

<!--
The org pack of FuguBSD/Tooling owns this file. Do not edit a synced
copy. Edit the canonical copy in FuguBSD/Tooling.
-->

# Review panel

Review the current change with three independent reviewers, in at most three
rounds. You dispatch each agent, and a `fixer` agent makes every fix.

## Your part

- Dispatch, merge the three reports, and write the ledger.
- After the first launch of a round, edit no repository file. A file under
  `scratch/` is scratch space, and not a repository file.
- Reject a finding in the ledger with a reason that cites the code, the
  specification, or a decision.

## The ledger

`scratch/review/ledger.md` holds one line for each finding:

```
| # | Round | File:line | Severity | Members | Disposition |
```

- A severity is `blocker` or `minor`.
- A disposition is `open`, `accepted`, `fixed`, `rejected: <reason>`, `dropped`,
  or `recorded`.
- A blocker that two members report becomes `accepted`. Two reports match when
  they name the same file and the same defect.
- A blocker of one member stays `open`. The next round confirms it or drops it.
- A minor finding becomes `recorded`. No round fixes it.

## The round

1. Run `make check </dev/null`. Commit every change.
2. In round one, write the base diff:
   `git diff <base>...HEAD > scratch/review/base.diff`.
3. Launch three `reviewer` agents in parallel with the prompt below. Round one
   reads `scratch/review/base.diff`, and a later round reads
   `scratch/review/fix-<N-1>.diff`.
4. Merge the three reports into the ledger.
5. In round one and round two, launch one `fixer` agent when the round holds an
   accepted finding. Give it the repository path, the diff path, and the ledger
   path.
6. After the fixer commits, write the fix diff:
   `git diff <round commit>...HEAD > scratch/review/fix-<N>.diff`. When the
   fixer commits nothing, write no file.
7. Stop after a round with no quorum finding, after a round whose fixer commits
   nothing, or after round three. Round three runs no fixer.

Round two and round three review the fix diff of the last round, and each file
that the fixer report cites.

## The review prompt

Send this prompt to each reviewer, with the four values in place:

> Review the change of the repository at `<repository path>`. The diff is at
> `<diff path>`, and this is round `<N>` of three. Read the diff file, each file
> that the diff names, and the `CLAUDE.md` of each changed directory. Do not
> derive the diff, and do not run a gate. Report each defect. A defect is a
> correctness error, a specification conflict, an absent test, an absent
> specification update, or a rule violation. Do not report a defect that
> `make check` catches, and do not report a style preference. Report at most ten
> findings, one line for each: `FILE:LINE — DEFECT [blocker|minor]`. Report "no
> findings" when the change holds none. The ledger is at `<ledger path>`.

Add these two sentences in round two and round three:

> The diff at `<diff path>` is the fix diff of the last round. Confirm each
> `fixed` entry of the ledger against it, report a new defect inside that scope
> only, and confirm or drop each `open` entry.

## The round table

The pull request body holds the result of the panel:

```
| Round | Findings | Quorum | Residue |
| ----- | -------- | ------ | ------- |
| 1     | 7        | 3      | —       |
```

The residue is each quorum finding of round three, each `open` entry, and each
quorum finding that no fixer fixed. The operator decides each one.
