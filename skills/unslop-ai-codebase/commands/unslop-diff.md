---
description: Unslop only the uncommitted changes, then show a summary using the unslop-ai-codebase skill
---

Use the unslop-ai-codebase skill to de-slop the uncommitted changes only — do not touch any other files.

$ARGUMENTS

Uncommitted change summary:

!`git diff --stat HEAD && git status --short`

Restrict the rewrite to the files listed above (or the given paths if provided). Follow the skill exactly:
1. Save a pristine copy next to each file (`<file>.orig`) before editing.
2. Prune self-explanatory comments and AI writing patterns; keep step markers, background context, trade-off decisions, and every tooling pragma.
3. Verify every rewritten file: `bash skills/unslop-ai-codebase/scripts/check.sh "<file-path>"`. Fix and re-run on failure; retry at most 5 times before falling back to your own judgment.
4. Finish with the skill's brief change report, then show the final diff stat (`git diff --stat`). Do not stage or commit anything.
