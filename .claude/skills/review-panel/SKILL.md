---
name: review-panel
description:
  Review the change set of this branch with a panel of independent sub-agents
  that share one review prompt. Use before a merge, or when the user asks for a
  panel review.
---

# Review panel

Review the current change with a panel of independent sub-agents. Resolve each
quorum finding before the merge.

## Procedure

1. Collect the change: the diff against the base branch, and the list of changed
   files.
2. Launch three sub-agents in parallel. Give each sub-agent the same input: the
   review prompt below, plus the diff. Do not share findings between the
   sub-agents.
3. Collect the findings. Two findings match when they name the same file and the
   same defect.
4. A finding that two or more sub-agents report is a quorum finding.
5. Resolve each quorum finding: correct the change, or record why the finding
   does not apply. A recorded rejection needs a reason that cites the code, the
   specification, or a decision.
6. Repeat the panel until no unresolved quorum finding remains.
7. Record the outcome in the pull request checklist.

## The review prompt

> Review this change as a skeptical engineer. Report each defect that you find:
> a correctness error, a specification conflict, a missing test, a missing
> specification update, a violation of the repository rules, or a
> writing-standard violation. For each finding, name the file, the line, and the
> defect, in one sentence each. Report at most ten findings. Do not report style
> preferences.
