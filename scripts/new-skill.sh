#!/usr/bin/env bash
#
# new-skill.sh — scaffold a new skill with a working evaluation gate.
#
# Usage:
#   ./scripts/new-skill.sh <skill-name> "<trigger-description>"
#
# Creates (patterned after skills/conventional-commit, but self-contained):
#   skills/<skill-name>/SKILL.md
#   skills/<skill-name>/scripts/check.sh        # placeholder stateless validator
#   skills/<skill-name>/evals/dataset.jsonl     # 4 starter fixtures (2 valid, 2 invalid)
#   skills/<skill-name>/evals/judge.py          # zero-dependency grader
#   skills/<skill-name>/evals/run_eval.sh       # executable eval entrypoint
#
# The scaffolded suite passes out of the box, so the evaluation gate is wired
# up before any real logic exists. Replace the placeholder rules, validator,
# and fixtures — but keep the gate.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NAME_REGEX='^[a-z0-9]+(-[a-z0-9]+)*$'

die() { echo "ERROR: $*" >&2; exit 1; }

if [ "$#" -ne 2 ]; then
  echo 'Usage: ./scripts/new-skill.sh <skill-name> "<trigger-description>"' >&2
  exit 1
fi

SKILL_NAME="$1"
SKILL_DESCRIPTION="$2"

if ! [[ "$SKILL_NAME" =~ $NAME_REGEX ]]; then
  die "skill name must be lowercase alphanumeric with hyphens (got: '$SKILL_NAME')"
fi
case "$SKILL_DESCRIPTION" in
  *'"'*)  die "description must not contain double quotes" ;;
  *'\'*)  die "description must not contain backslashes" ;;
  *'`'*)  die "description must not contain backticks" ;;
  *'$'*)  die "description must not contain dollar signs" ;;
esac
if [ -z "$SKILL_DESCRIPTION" ]; then
  die "description must not be empty"
fi
if [ -e "skills/$SKILL_NAME" ]; then
  die "skills/$SKILL_NAME already exists"
fi

SKILL_DIR="skills/$SKILL_NAME"
mkdir -p "$SKILL_DIR/scripts" "$SKILL_DIR/evals"

# --- SKILL.md ---------------------------------------------------------------
cat > "$SKILL_DIR/SKILL.md" <<EOF
---
name: $SKILL_NAME
description: $SKILL_DESCRIPTION
metadata:
  version: "0.0.1"
---
# $SKILL_NAME Skill

## Rules
1. Replace these placeholder rules with the real, verifiable rules of this skill.
2. Keep every rule concrete so evals can assert pass/fail outcomes.

## Mandatory Verification Step
Before completing a task that involves this skill, you MUST validate the work using the bundled script (run from this skill's directory; paths are relative to the skill root):
\`\`\`bash
bash scripts/check.sh "<input>"
\`\`\`
If the script exits with a non-zero code, read \`stderr\`, fix the problem, and re-run until it outputs \`PASS\`.
EOF

# --- scripts/check.sh -------------------------------------------------------
cat > "$SKILL_DIR/scripts/check.sh" <<'EOF'
#!/usr/bin/env bash
# Placeholder validator — replace with the real checks for this skill.
set -u

input="${1:-}"

if [ -z "$input" ]; then
  echo "ERROR: input is empty" >&2
  exit 1
fi

echo "PASS: non-empty input"
exit 0
EOF

# --- evals/dataset.jsonl ----------------------------------------------------
cat > "$SKILL_DIR/evals/dataset.jsonl" <<'EOF'
{"id": "valid_example_one", "input": "example input", "expected_exit_code": 0, "required_skill_terms": ["check.sh"]}
{"id": "valid_example_two", "input": "another example", "expected_exit_code": 0, "required_skill_terms": ["check.sh"]}
{"id": "invalid_empty_input", "input": "", "expected_exit_code": 1, "required_skill_terms": ["check.sh"]}
{"id": "invalid_missing_input", "expected_exit_code": 1, "required_skill_terms": ["check.sh"]}
EOF

# --- evals/judge.py ---------------------------------------------------------
cat > "$SKILL_DIR/evals/judge.py" <<'EOF'
#!/usr/bin/env python3
"""Zero-dependency judge for this skill.

Reads SKILL.md and evals/dataset.jsonl, then for every case:
  * asserts each required_skill_terms entry appears in SKILL.md, and
  * executes scripts/check.sh with the case input and compares the exit
    code against expected_exit_code.

Exits 0 only when every case passes.
"""

import json
import subprocess
import sys
from pathlib import Path

EVALS_DIR = Path(__file__).resolve().parent
SKILL_DIR = EVALS_DIR.parent
SKILL_MD = SKILL_DIR / "SKILL.md"
DATASET = EVALS_DIR / "dataset.jsonl"
CHECKER = SKILL_DIR / "scripts" / "check.sh"


def load_cases():
    cases = []
    with DATASET.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                cases.append(json.loads(line))
    return cases


def main():
    skill_md = SKILL_MD.read_text(encoding="utf-8")
    cases = load_cases()

    failures = 0
    for case in cases:
        reasons = []

        for term in case.get("required_skill_terms", []):
            if term not in skill_md:
                reasons.append(f"SKILL.md is missing required term {term!r}")

        proc = subprocess.run(
            [str(CHECKER), case.get("input", "")],
            capture_output=True,
            text=True,
        )
        if proc.returncode != case["expected_exit_code"]:
            reasons.append(
                f"expected exit code {case['expected_exit_code']}, "
                f"got {proc.returncode} (stderr: {proc.stderr.strip() or '<none>'})"
            )

        if reasons:
            failures += 1
            print(f"[FAIL] {case['id']}")
            for reason in reasons:
                print(f"       - {reason}")
        else:
            print(f"[PASS] {case['id']}")

    print(f"{len(cases) - failures}/{len(cases)} cases passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
EOF

# --- evals/run_eval.sh ------------------------------------------------------
cat > "$SKILL_DIR/evals/run_eval.sh" <<'EOF'
#!/usr/bin/env bash
#
# run_eval.sh — evaluation gate for this skill. Exits 0 only if every check passes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
SKILL_MD="$SKILL_DIR/SKILL.md"
CHECKER="$SKILL_DIR/scripts/check.sh"

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
echo "[OK] bash -n: scripts/check.sh"

# 3. Run the dataset judge.
python3 "$SCRIPT_DIR/judge.py"

echo "[OK] $SKILL_NAME eval suite passed"
EOF

chmod +x "$SKILL_DIR/scripts/check.sh" "$SKILL_DIR/evals/run_eval.sh"

echo "Created skill scaffold at $SKILL_DIR"
echo "Next steps:"
echo "  1. Edit $SKILL_DIR/SKILL.md rules."
echo "  2. Implement $SKILL_DIR/scripts/check.sh."
echo "  3. Update $SKILL_DIR/evals/dataset.jsonl fixtures."
echo "  4. Run ./skills/$SKILL_NAME/evals/run_eval.sh — it must exit 0."
