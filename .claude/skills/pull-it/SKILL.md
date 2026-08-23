---
name: pull-it
description:
  Merge the current branch to main through a pull request. Use for a minor-level
  or major-level change, such as a new feature.
---

# Pull it

Merge a minor-level or major-level change to `main` through a pull request.

## Procedure

1. Squash in-session review fixes into the commits that they correct.
2. Push the branch: `git push --force-with-lease origin HEAD`. Open a pull
   request when none exists.
3. Watch the checks: `gh pr checks --watch`.
4. When a check fails, correct the cause. Push the fix. Repeat until every check
   passes.
5. Run the [review panel](../review-panel/SKILL.md). Resolve each quorum
   finding. When you push a fix, return to step 3.
6. Squash merge: `gh pr merge --squash --delete-branch`.
