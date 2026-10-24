# AGENTS.md — OpenCode Development & Skill Authoring Guide

## 1. Spec Lookups via Context7 MCP (Dev-Time Only)
This project is developed using **OpenCode** with the **Context7 MCP** server configured in `opencode.json`.
Whenever you create, modify, or validate `plugin.json` or `skills/*/SKILL.md`, query Context7 first to verify compliance with the latest specifications:
- **Agent Skills Spec:** Reference `websites/agentskills_io` (`https://context7.com/websites/agentskills_io`) for `SKILL.md` frontmatter, progressive disclosure, and directory rules.
- **Agent Plugins 1.0 Spec:** Reference `websites/agent-plugins` (`https://context7.com/websites/agent-plugins`) for `plugin.json` schema, versioning, and `${PLUGIN_DATA}` rules.

## 2. Core Architecture Rules (Zero-MCP Plugin Output)
1. **No `mcp.json` in the Plugin:** While we use Context7 MCP *inside OpenCode to develop this repo*, the published plugin itself must remain **100% Zero-MCP**. Never create `mcp.json`.
2. **Stateless CLI Scripts:** All runtime checks and tools must live as stateless scripts inside `skills/<skill-name>/scripts/` executed via the agent's native bash tool.
3. **Isolated Per-Skill Evals:** Every skill under `skills/<skill-name>/` MUST contain an executable `evals/run_eval.sh` and `evals/dataset.jsonl`.

## 3. How to Add a New Skill
1. **Consult Context7:** Verify frontmatter and naming constraints against `websites/agentskills_io`.
2. **Scaffold:** Run `./scripts/new-skill.sh <skill-name> "<trigger-description>"`.
3. **Implement:**
   - Edit `skills/<skill-name>/SKILL.md` (ensure `name` matches the folder name and is lowercase alphanumeric with hyphens).
   - Add deterministic helper or validation scripts in `skills/<skill-name>/scripts/`.
   - Add at least 4 pass/fail test fixtures in `skills/<skill-name>/evals/dataset.jsonl`.
4. **Evaluate:** Run `./skills/<skill-name>/evals/run_eval.sh`. Do not mark a task complete until it exits with code `0`.
5. **Release:** Run `./scripts/release.sh <MAJOR.MINOR.PATCH> [--changed-only]` to execute all skill evals, sync versions, and create a Git tag.
