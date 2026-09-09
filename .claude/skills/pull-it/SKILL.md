---
name: pull-it
description:
  Merge the current branch to main through a pull request. Use for a minor-level
  or major-level change, such as a new feature.
---

<!--
The org pack of FuguBSD/Tooling owns this file. Do not edit a synced
copy. Edit the canonical copy in FuguBSD/Tooling.
-->

# Pull it

Merge a minor-level or major-level change to `main` through a pull request.

## The size gate

One change set carries one plan or one feature. Split the branch when it carries
more. A wide change set gives each review round more text than one round can
settle.

## Procedure

1. Squash in-session review fixes into the commits that they correct.
2. Push the branch: `git push --force-with-lease origin HEAD`. Open a pull
   request when none exists.
3. Watch the checks: `gh pr checks --watch`. When a check fails, dispatch a
   `fixer` agent with the failure log. Push the fix commit, and watch the checks
   again.
4. Run the [review panel](../review-panel/SKILL.md) one time. It runs at most
   three rounds.
5. Push each fix commit of the panel. Watch the checks once more, and repair a
   failure as step 3 states.
6. Put the round table and the residue in the pull request body. The operator
   decides each residue entry.
7. Squash merge: `gh pr merge --squash --delete-branch`.

## Stop

Stop after the merge. The next change starts in a new session.
