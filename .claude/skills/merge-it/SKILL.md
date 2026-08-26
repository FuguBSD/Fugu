---
name: merge-it
description:
  Merge the current branch to main without a pull request. Use for a patch-level
  change such as a fix, a chore, a tooling update, or maintenance.
---

<!--
The org pack of FuguBSD/Tooling owns this file. Do not edit a synced
copy. Edit the canonical copy in FuguBSD/Tooling.
-->

# Merge it

Merge a patch-level change to `main` without a pull request. The squash merge
keeps the history of `main` clean.

## Procedure

1. Update `main` from the remote. Rebase the branch onto `main`.
2. Run `make check`. It must pass.
3. Squash merge the branch into `main`. Write one Conventional Commit message.
4. Push `main`. Delete the branch.
5. When CI runs on `main`, watch it. Fix a failure immediately.
