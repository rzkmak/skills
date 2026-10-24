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

## Usage

Agents activate skills by the `description` frontmatter. For example, when
drafting a commit message, the `conventional-commit` skill requires the agent to
verify itself before committing:

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

## Commands (OpenCode)

Skills are invoked by the model when a task matches their description; commands
are explicit entry points you type. This repo serves both:

- `.opencode/commands/commit.md` → `/commit [instructions]` — drafts, splits,
  and validates the current changes using the `conventional-commit` skill, with
  the diff summary attached automatically.
- `opencode.json` registers `"skills": ["./skills"]`, so opening this repo in
  OpenCode makes every skill in `skills/` available with no install step.

Commands are OpenCode-specific and project-scoped; to use `/commit` in other
projects, copy the file to `~/.config/opencode/commands/`.

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
```

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
│   └── release.sh           # evals, version bump, git tag
└── skills/
    └── conventional-commit/
        ├── SKILL.md
        ├── scripts/
        │   ├── check-commit-msg.sh
        │   └── check-commit-plan.sh
        └── evals/
            ├── dataset.jsonl
            ├── judge.py
            └── run_eval.sh
```
