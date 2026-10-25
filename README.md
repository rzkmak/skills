# skills

[![skills.sh](https://skills.sh/b/rzkmak/skills)](https://skills.sh/rzkmak/skills)

A personal collection of **Zero-MCP** agent skills ([Agent Plugins 1.0](https://agent-plugins.org)) by rzkmak —
verifiable developer workflow skills, each with an embedded evaluation gate, so agents prove their work with plain
scripts instead of calling MCP servers at runtime.

## Why Zero-MCP?

Runtime tooling here is deliberately boring: stateless `bash`/`python3` scripts
inside each skill's `scripts/` directory, invoked through the agent's native
shell tool. Nothing to install, no servers to keep alive, fully deterministic —
and therefore testable in CI. The **Context7 MCP** server configured in
`opencode.json` is a *development-time* aid for spec lookups inside OpenCode; it
is never shipped with the plugin. The published artifact contains **no
`mcp.json`**, and `scripts/release.sh` enforces that policy on every release.

## Requirements

- `bash` (runtime validators)
- `python3` (evaluation judges — zero third-party dependencies)
- `git` (releases only)
- An agent that supports the Agent Plugins 1.0 layout

## Installation

Install a single skill into your agent with the [skills CLI](https://skills.sh)
(works with OpenCode, Claude Code, Cursor, and 75+ other agents):

```bash
npx skills add rzkmak/skills --skill conventional-commit
npx skills add rzkmak/skills --skill implement-go-api
npx skills add rzkmak/skills --skill unslop-ai-codebase
```

Or install every skill in this repo:

```bash
npx skills add rzkmak/skills
```

Or install as an Agent Plugin (for Agent Plugins 1.0 clients):

```bash
git clone https://github.com/rzkmak/skills ~/.agents/plugins/skills
```

The manifest is `plugin.json`; skills are auto-discovered from `skills/`.

## Skills

| Skill | Entry point | What it does |
| --- | --- | --- |
| `conventional-commit` | model-invoked + `/commit`, `/commit-push` | Draft, split, and validate Conventional Commit messages before committing. |
| `implement-go-api` | model-invoked | Enforce a standard domain-modular layout for Go + Gin APIs. |
| `unslop-ai-codebase` | `/unslop`, `/unslop-diff` only (`disable-model-invocation: true`) | Remove AI slop from comments, docs, and prose while preserving step markers, background context, and decisions; `scripts/check.sh` verifies pragmas and runtime code survive the rewrite. |

## Usage

Agents activate model-invocable skills by the `description` frontmatter. For
example, when drafting a commit message, the `conventional-commit` skill
requires the agent to verify itself before committing:

```bash
./skills/conventional-commit/scripts/check-commit-msg.sh "feat(auth): add jwt token refresh endpoint"
# PASS: Valid conventional commit
```

If the validator exits non-zero, the agent reads `stderr`, fixes the message,
and re-runs — at most 5 times. After 5 failed retries it stops looping and
falls back to its own judgment: proceed with stated reasoning that the
validator is wrong for the case, or ask the user — never keep guessing.

For large diffs, the skill guides splitting into at most 5 single-purpose
commits (from known context, or by inferring purpose from the changes) and
validates the whole plan upfront:

```bash
./skills/conventional-commit/scripts/check-commit-plan.sh \
  "feat(auth): add jwt token refresh endpoint" \
  "fix(parser): handle empty payload" \
  "docs: explain token refresh flow"
# PASS: Valid commit plan (3 commits, max 5)
```

## Commands (OpenCode & Claude Code)

Skills are invoked by the model when a task matches their description; commands
are explicit entry points you type. Skills with `disable-model-invocation:
true` (e.g. `unslop-ai-codebase`) never trigger on their own — their commands
are the only way to run them. This repo serves both:

- Command templates travel inside each skill (`skills/<name>/commands/*.md`) —
  `npx skills add` copies only skill folders, so that is how they ride along.
- One installer installs **every** skill's commands in one action, for both
  agents:

```bash
# from anywhere (clones the repo if needed) — installs globally by default
curl -fsSL https://raw.githubusercontent.com/rzkmak/skills/main/scripts/install-commands.sh | bash

# or from a checkout: scope, agents, repo dir
./scripts/install-commands.sh global opencode,claude-code
./scripts/install-commands.sh project claude-code
```

Targets: OpenCode `.opencode/commands/` (project) or
`~/.config/opencode/commands/` (global); Claude Code `.claude/commands/`
(project) or `~/.claude/commands/` (global). Command filenames must be unique
repo-wide; the eval gate keeps shipped templates and installed copies in sync.

Working inside this repo with OpenCode: `opencode.json` registers
`"skills": ["./skills"]`, and the commands work once installed — run
`./scripts/install-commands.sh project` in this checkout (the installed
copies stay untracked, as local working files).

## Development (OpenCode + Context7)

This repository is developed inside **OpenCode** with the **Context7 MCP**
configured in `opencode.json` for live spec lookups (Agent Skills + Agent
Plugins 1.0). That MCP server is a dev-time tool only and is never part of the
published plugin. See `AGENTS.md` for the full authoring rules.

### Add a new skill

```bash
./scripts/new-skill.sh my-skill "Use when doing X"
# implement rules + scripts + fixtures, then gate it:
./skills/my-skill/evals/run_eval.sh   # must exit 0
```

The scaffolder generates a working evaluation gate (a passing placeholder
validator plus 4 starter fixtures) so every skill is born testable.

### Run the eval suite

```bash
./skills/conventional-commit/evals/run_eval.sh
./skills/implement-go-api/evals/run_eval.sh
```

### Optional LLM behavioral evals

Skills may also carry an LLM behavioral suite (`evals/run_eval_llm.sh`, pytest +
[deepeval](https://github.com/confident-ai/deepeval) `GEval` as the judge). The
model under test generates behavior with `SKILL.md` in context; bundled
deterministic checkers grade everything they can, and `GEval` judges only what
checkers cannot express (boundary decisions, rationale quality). It is never
wired into the deterministic gate, CI, or releases — run it explicitly when
changing a skill's guidance:

```bash
export OPENAI_BASE_URL=...      # OpenAI-compatible endpoint
export OPENAI_API_KEY=...       # never echoed or written anywhere
export OPENAI_DEFAULT_MODEL=...
./skills/implement-go-api/evals/run_eval_llm.sh
```

Dependencies install into a gitignored per-skill venv (`evals/llm/.venv`);
a missing environment variable is a loud error, never a silent fallback.

## Release

```bash
./scripts/release.sh 0.2.0                 # run all skill evals, bump, commit, tag
./scripts/release.sh 0.2.1 --changed-only  # evaluate only skills changed since the last tag
```

`release.sh` refuses to run if `mcp.json` exists in the repo root (Zero-MCP
policy), if `plugin.json` is not valid JSON, or if any skill eval fails.

## Layout

```text
.
├── opencode.json            # dev-time config: Context7 MCP + skills source registration
├── .opencode/
│   └── commands/
│       └── commit.md        # /commit — explicit entry into the conventional-commit skill
├── plugin.json              # Agent Plugins 1.0 manifest (Zero-MCP: no mcp.json)
├── AGENTS.md                # authoring guide for OpenCode agents
├── README.md
├── scripts/
│   ├── new-skill.sh         # scaffold a skill + eval gate
│   ├── install-commands.sh  # install all skills' commands for OpenCode/Claude Code
│   └── release.sh           # evals, version bump, git tag
└── skills/
    ├── conventional-commit/
    │   ├── SKILL.md
    │   ├── commands/
    │   │   ├── commit.md      # /commit template (travels with the skill)
    │   │   └── commit-push.md # /commit-push template
    │   ├── scripts/
    │   │   ├── check-commit-msg.sh
    │   │   └── check-commit-plan.sh
    │   └── evals/
    │       ├── dataset.jsonl
    │       ├── judge.py
    │       └── run_eval.sh
    └── implement-go-api/
    │       ├── SKILL.md          # domain-modular layout standard for Go + Gin
    │       ├── scripts/
    │       │   ├── check_layout.sh   # validate a whole project directory
    │       │   └── check_snippet.sh  # validate a single Go file
    │       └── evals/
    │           ├── dataset.jsonl
    │           ├── fixtures/     # valid + invalid sample projects and snippets
    │           ├── judge.py
    │           ├── run_eval.sh   # deterministic gate (must exit 0)
    │           └── llm/          # optional behavioral suite (deepeval GEval)
    │               ├── test_implement_go_api.py
    │               └── .venv/    # gitignored, created by run_eval_llm.sh
    └── unslop-ai-codebase/
        ├── SKILL.md          # prune AI slop from comments/docs; disable-model-invocation
        ├── commands/
        │   ├── unslop.md         # /unslop template
        │   └── unslop-diff.md    # /unslop-diff template (uncommitted changes only)
        ├── scripts/
        │   └── check.sh          # pragmas intact + runtime code unchanged after rewrite
        └── evals/
            ├── dataset.jsonl
            ├── fixtures/         # before/after rewrite samples (pass + fail)
            ├── judge.py
            └── run_eval.sh       # deterministic gate (must exit 0)
```
