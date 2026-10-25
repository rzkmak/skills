#!/usr/bin/env bash
#
# run_eval_llm.sh — optional LLM behavioral eval suite for the
# implement-go-api skill (deepeval GEval as the judge).
#
# NOT part of the deterministic gate (evals/run_eval.sh) and never a completion
# gate: judge scores are probabilistic and this suite costs tokens. Run it
# explicitly when changing SKILL.md guidance, or when the user asks.
#
# Endpoint, credentials and model come exclusively from the environment:
#   OPENAI_BASE_URL, OPENAI_API_KEY, OPENAI_DEFAULT_MODEL
# A missing variable is a loud error — never a silent fallback. The key value
# is never echoed, logged, or written to any file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/llm/.venv"

# 1. Loud environment check. Only the presence of the variables is inspected.
for var in OPENAI_BASE_URL OPENAI_API_KEY OPENAI_DEFAULT_MODEL; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: environment variable $var is not set — the LLM eval suite requires it (see skills/implement-go-api/evals/llm/)" >&2
    exit 1
  fi
done
echo "[OK] LLM eval environment: OPENAI_BASE_URL, OPENAI_API_KEY, OPENAI_DEFAULT_MODEL are set"

# 2. Install deepeval + pytest into a local, gitignored venv (test-only deps).
if [ ! -x "$VENV/bin/python" ]; then
  echo "[..] creating virtualenv at $VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --disable-pip-version-check --quiet deepeval pytest certifi
fi

# 3. Run the behavioral tests. Generation and judging share the endpoint and
#    model already configured via the environment above.
exec "$VENV/bin/python" -m pytest "$SCRIPT_DIR/llm/test_implement_go_api.py" -v "$@"
