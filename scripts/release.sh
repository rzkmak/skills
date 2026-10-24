#!/usr/bin/env bash
#
# release.sh — evaluation gate, version bump, and git tag for this plugin.
#
# Usage:
#   ./scripts/release.sh <MAJOR.MINOR.PATCH> [--changed-only]
#
# Steps:
#   1. Enforce the Zero-MCP policy: mcp.json must NOT exist in the repo root.
#   2. Validate that plugin.json parses as JSON.
#   3. Run evals/run_eval.sh for every skill — or, with --changed-only, only
#      for skills changed since the most recent git tag.
#   4. Bump the version in plugin.json and in every skills/*/SKILL.md.
#   5. Commit the bump and create the v<MAJOR.MINOR.PATCH> tag.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'

die() { echo "ERROR: $*" >&2; exit 1; }

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo 'Usage: ./scripts/release.sh <MAJOR.MINOR.PATCH> [--changed-only]' >&2
  exit 1
fi

VERSION="$1"
CHANGED_ONLY=0
if [ "${2:-}" = "--changed-only" ]; then
  CHANGED_ONLY=1
fi

if ! [[ "$VERSION" =~ $VERSION_REGEX ]]; then
  die "version '$VERSION' is not in MAJOR.MINOR.PATCH form (e.g. 1.2.3)"
fi

# 1. Zero-MCP policy.
if [ -f mcp.json ]; then
  die "mcp.json found in repo root — this plugin is Zero-MCP by policy; remove it"
fi

# 2. Manifest sanity.
if ! python3 -c 'import json; json.load(open("plugin.json"))' >/dev/null 2>&1; then
  die "plugin.json is not valid JSON"
fi

# 3. Git sanity.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "not inside a git repository — run 'git init' first"
fi
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  die "tag v$VERSION already exists"
fi
if [ ! -d skills ]; then
  die "skills/ directory not found"
fi

# Select skills to evaluate.
LAST_TAG=""
if git describe --tags --abbrev=0 >/dev/null 2>&1; then
  LAST_TAG="$(git describe --tags --abbrev=0)"
fi

TARGETS=""
if [ "$CHANGED_ONLY" -eq 1 ] && [ -n "$LAST_TAG" ]; then
  echo "--> --changed-only: evaluating skills changed since $LAST_TAG"
  TARGETS="$(git diff --name-only "$LAST_TAG" -- skills/ | cut -d/ -f2 | sort -u)"
else
  TARGETS="$(find skills -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort -u)"
fi

if [ -z "$TARGETS" ]; then
  echo "--> no skills to evaluate"
else
  for skill in $TARGETS; do
    if [ ! -d "skills/$skill" ]; then
      continue  # path was deleted since the last tag
    fi
    eval_sh="skills/$skill/evals/run_eval.sh"
    if [ ! -x "$eval_sh" ]; then
      die "$eval_sh is missing or not executable"
    fi
    echo "--> evaluating skills/$skill"
    "$eval_sh"
  done
fi

# 4. Bump versions.
python3 - "$VERSION" <<'PY'
import json
import sys

version = sys.argv[1]
with open("plugin.json", encoding="utf-8") as fh:
    manifest = json.load(fh)
manifest["version"] = version
with open("plugin.json", "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
print(f"--> plugin.json version -> {version}")
PY

for skill_md in skills/*/SKILL.md; do
  if [ ! -f "$skill_md" ]; then
    continue
  fi
  sed -E "s|^([[:space:]]*version:[[:space:]]*\")[^\"]*(\")|\1${VERSION}\2|" \
    "$skill_md" > "$skill_md.tmp" && mv "$skill_md.tmp" "$skill_md"
  echo "--> $skill_md version -> $VERSION"
done

# 5. Commit + tag.
git add plugin.json skills
if git diff --cached --quiet; then
  echo "--> nothing to commit (versions already at $VERSION)"
else
  git commit -m "chore(release): bump version to $VERSION"
fi
git tag "v$VERSION"
echo "--> released v$VERSION"
