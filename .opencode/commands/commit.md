---
description: Draft, split, and validate commit messages using the conventional-commit skill
---

Load the @conventional-commit skill and commit the current changes.

$ARGUMENTS

Current change summary:

!`git diff --stat HEAD && git status --short`

Follow the skill exactly: split large diffs along task or purpose boundaries (max 5 commits), validate every message with the bundled check scripts before committing, and retry at most 5 times before falling back to your own judgment.
