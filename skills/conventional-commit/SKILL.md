---
name: conventional-commit
description: Use when drafting, formatting, or validating Git commit messages to ensure strict compliance with the Conventional Commits specification.
metadata:
  version: "0.1.0"
---
# Conventional Commit Skill

## Rules
1. Format every commit message header as: `<type>(<optional-scope>): <description>`
2. Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
3. Keep the header line under 72 characters, imperative mood, lowercase description, and no trailing period.

## Mandatory Verification Step
Before presenting a commit message or running `git commit`, you MUST validate the message using the bundled script:
```bash
./skills/conventional-commit/scripts/check-commit-msg.sh "<commit-message-header>"
```
If the script exits with a non-zero code, read `stderr`, fix the message, and re-run until it outputs `PASS`.
