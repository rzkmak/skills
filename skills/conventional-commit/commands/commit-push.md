---
description: Commit with the conventional-commit skill, then push the branch immediately
---

Use the conventional-commit skill to commit the current changes, then push the branch to its remote as soon as the commits are in.

$ARGUMENTS

Current change summary:

!`git diff --stat HEAD && git status --short`

Follow the skill exactly: split large diffs along task or purpose boundaries (max 5 commits), validate every message with the bundled check scripts before committing, and retry at most 5 times before falling back to your own judgment.

Once the final commit succeeds, push immediately: run `git push`, or `git push -u origin HEAD` if the branch has no upstream yet. Never force-push; if the push is rejected, show the error and stop so the user can decide.
