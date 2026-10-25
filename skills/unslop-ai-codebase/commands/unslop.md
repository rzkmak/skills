---
description: Remove AI slop from code comments, docs, or prose using the unslop-ai-codebase skill
---

Use the unslop-ai-codebase skill to de-slop the given target.

$ARGUMENTS

Uncommitted change summary:

!`git diff --stat HEAD && git status --short`

If no target was given above, apply the skill to the uncommitted changes listed here; otherwise operate only on the given paths.

Follow the skill exactly:
1. For each file, save a pristine copy next to it (`<file>.orig`) before editing, so the validator can diff against the original.
2. Prune self-explanatory comments and AI writing patterns; keep step markers, background context, trade-off decisions, and every tooling pragma (`//nolint`, `# noqa`, `# type: ignore`, `// @ts-expect-error`, `/* istanbul ignore next */`, `//go:build`, `//go:generate`, ...).
3. Verify every rewritten file before finishing: `bash skills/unslop-ai-codebase/scripts/check.sh "<file-path>"`. Fix and re-run on failure; retry at most 5 times before falling back to your own judgment.
4. Report briefly what was removed and what was preserved.
