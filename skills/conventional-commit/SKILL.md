---
name: conventional-commit
description: Use when drafting, formatting, validating, or splitting Git commit messages to ensure strict compliance with the Conventional Commits specification.
metadata:
  version: "0.1.0"
---
# Conventional Commit Skill

## Rules
1. Format every commit message header as: `<type>(<optional-scope>): <description>`
2. Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
3. Keep the header line under 72 characters, imperative mood, lowercase description, and no trailing period.

## Splitting Large Diffs
Treat a diff as large when it mixes unrelated concerns — practically, when it touches more than ~10 files or cannot be explained in one sentence.

When the diff is large:
1. **Known context:** Look at the current context (issues, todos, branch goals, session tasks). If the diff spans multiple ongoing tasks, split the commits along task boundaries.
2. **Unknown context:** If the purpose is unclear, gather the changes first — read `git diff`, group the files and hunks that serve one purpose — and infer the purpose of each group. If there is more than one purpose, split the commits along purpose boundaries.
3. **Do not over-split:** A single change set must become at most 5 commits (max 5). If you identify more than five groups, merge the smaller related ones until you have 5 or fewer. Prefer the fewest commits that keep each commit single-purpose.

Stage each part separately (`git add <paths>` or `git add -p`) and commit one part at a time.

## Mandatory Verification Step
Before presenting a commit message or running `git commit`, validate using the bundled scripts (run from this skill's directory; paths are relative to the skill root):
```bash
# single commit
bash scripts/check-commit-msg.sh "<commit-message-header>"

# multi-commit plan (validates every header and enforces max 5 commits)
bash scripts/check-commit-plan.sh "<header-1>" "<header-2>" "<header-3>"
```
### Retry Limit
If a script exits with a non-zero code, read `stderr`, fix the messages (or merge the plan), and re-run. Retry at most 5 times — do not loop forever.

If verification still fails after 5 retries, stop retrying and rely on your own judgment:
- If you are confident the message or plan is valid and the validator is wrong for this case, proceed and state your reasoning next to the commit.
- If you are not confident, ask the user how to proceed instead of guessing.

## Slash Command (/commit)
This skill ships an optional explicit entry point: the `/commit` command (`commands/commit.md` inside this skill) for OpenCode and Claude Code. If the user wants `/commit` and it is not installed, point them to the repo-level installer — one action installs every skill's commands:
```bash
curl -fsSL https://raw.githubusercontent.com/rzkmak/skills/main/scripts/install-commands.sh | bash
```
or, from a checkout of the repo: `./scripts/install-commands.sh [global|project] [agents]` (scope defaults to `global`, agents to `opencode,claude-code`). Only install commands when the user asks for it.
