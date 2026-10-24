#!/usr/bin/env bash
#
# run_eval.sh — evaluation gate for the conventional-commit skill.
# Exits 0 only if every check passes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
SKILL_MD="$SKILL_DIR/SKILL.md"
CHECKER="$SKILL_DIR/scripts/check-commit-msg.sh"
PLAN_CHECKER="$SKILL_DIR/scripts/check-commit-plan.sh"

# 1. Frontmatter: name must match the skill folder, description must be present.
SKILL_NAME="$(basename "$SKILL_DIR")"
front_name="$(awk '/^name:/{print $2; exit}' "$SKILL_MD")"
front_desc="$(awk '/^description:/{sub(/^description: */, ""); print; exit}' "$SKILL_MD")"

if [ "$front_name" != "$SKILL_NAME" ]; then
  echo "FAIL: SKILL.md frontmatter name is '${front_name:-<missing>}', expected '$SKILL_NAME'" >&2
  exit 1
fi
if [ -z "$front_desc" ]; then
  echo "FAIL: SKILL.md frontmatter description is missing" >&2
  exit 1
fi
echo "[OK] frontmatter: name=$SKILL_NAME, description present"

# 2. Syntax-check the runtime validators.
bash -n "$CHECKER"
bash -n "$PLAN_CHECKER"
echo "[OK] bash -n: check-commit-msg.sh, check-commit-plan.sh"

# 2b. Inside this repo, shipped command templates must match installed copies.
ROOT_DIR="$(cd "$SKILL_DIR/../.." && pwd)"
if [ -f "$ROOT_DIR/plugin.json" ]; then
  for template in "$SKILL_DIR"/commands/*.md; do
    [ -f "$template" ] || continue
    installed="$ROOT_DIR/.opencode/commands/$(basename "$template")"
    if [ -f "$installed" ]; then
      diff -q "$installed" "$template" >/dev/null || {
        echo "FAIL: $installed differs from $template — run ./scripts/install-commands.sh project" >&2
        exit 1
      }
    fi
  done
  echo "[OK] commands: shipped templates match installed copies"
fi

# 3. Run the dataset judge.
python3 "$SCRIPT_DIR/judge.py"

echo "[OK] $SKILL_NAME eval suite passed"
