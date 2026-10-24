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
4. **No Autonomous Releases:** When committing new changes, never decide to release on your own. Do NOT run `scripts/release.sh`, create Git tags, or bump versions unless the user explicitly asks for it. Committing is fine; tagging and version bumps are human decisions.
5. **Per-Skill Commands (optional):** A skill may ship agent command templates as `skills/<skill-name>/commands/*.md`. Command filenames must be unique repo-wide; users install all of them at once for OpenCode and Claude Code via `scripts/install-commands.sh`.

## 3. How to Add a New Skill
1. **Consult Context7:** Verify frontmatter and naming constraints against `websites/agentskills_io`.
2. **Scaffold:** Run `./scripts/new-skill.sh <skill-name> "<trigger-description>"`.
3. **Implement:**
   - Edit `skills/<skill-name>/SKILL.md` (ensure `name` matches the folder name and is lowercase alphanumeric with hyphens).
   - Add deterministic helper or validation scripts in `skills/<skill-name>/scripts/`.
   - Add at least 4 pass/fail test fixtures in `skills/<skill-name>/evals/dataset.jsonl`.
4. **Evaluate:** Run `./skills/<skill-name>/evals/run_eval.sh`. Do not mark a task complete until it exits with code `0`. If the skill has an LLM eval (`evals/run_eval_llm.sh`, see §4) and you changed its `SKILL.md` guidance, run that too — it is optional, never a completion gate.
5. **Release (only on explicit request):** When — and only when — the user asks for a release, run `./scripts/release.sh <MAJOR.MINOR.PATCH> [--changed-only]` to execute all skill evals, sync versions, and create a Git tag. Never choose the version, the timing, or whether to release at all by yourself.

## 4. LLM Evals (deepeval, Optional Suite)
Deterministic evals (`evals/run_eval.sh`) remain the blocking gate: they must pass with exit code `0` and never require network access or API keys. LLM-based behavioral evals are a separate, optional suite next to them.

1. **Environment (always):** Every LLM evaluation in this repository — any skill, any script, present or future — takes its endpoint, credentials, and model exclusively from these three environment variables, and from nothing else:
   - `OPENAI_BASE_URL` — the OpenAI-compatible endpoint
   - `OPENAI_API_KEY` — its key
   - `OPENAI_DEFAULT_MODEL` — the model to use
   Never hardcode an endpoint, key, or model name anywhere in the repo, and never invent alternative variable names. The key value is never echoed, logged, or written to any file — scripts may only check that the variables are set. A missing variable is a loud error, never a silent fallback. Generation and judging share the same endpoint and model.
2. **Layout:** LLM evals live at `skills/<skill-name>/evals/llm/` as pytest tests (e.g. `test_<skill-name>.py`), with the entry point at `skills/<skill-name>/evals/run_eval_llm.sh`.
3. **Framework:** Use [deepeval](https://github.com/confident-ai/deepeval) (`GEval` as the judge). `deepeval` is a test-only dependency: never import it from `skills/*/scripts/` or the deterministic gate. `run_eval_llm.sh` installs it into a local venv at `evals/llm/.venv` (gitignored, never committed).
4. **When it runs:** Never wire it into `run_eval.sh`, CI gates, or release checks, and never require exit code `0` from it to mark a task complete — judge scores are probabilistic and it costs tokens. Run it explicitly when changing a skill's `SKILL.md` guidance, or when the user asks.
5. **Grading pattern:** The model under test generates behavior with `SKILL.md` in context. Bundled deterministic checkers grade everything they can (formats, exit codes, commit-count ranges); `GEval` judges only what checkers cannot express (splitting quality, type semantics). Reference plans in a scenario anchor the judge and are compared semantically, never literally.
