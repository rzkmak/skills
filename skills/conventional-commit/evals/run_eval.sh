#!/usr/bin/env bash
#
# run_eval.sh — evaluation gate for the conventional-commit skill.
# Exits 0 only if every check passes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
SKILL_MD="$SKILL_DIR/SKILL.md"
CHECKER="$SKILL_DIR/scripts/check-commit-msg.sh"

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

# 2. Syntax-check the runtime validator.
bash -n "$CHECKER"
echo "[OK] bash -n: scripts/check-commit-msg.sh"

# 3. Run the dataset judge.
python3 "$SCRIPT_DIR/judge.py"

echo "[OK] $SKILL_NAME eval suite passed"
