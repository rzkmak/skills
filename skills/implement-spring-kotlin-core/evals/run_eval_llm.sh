#!/usr/bin/env bash
#
# run_eval_llm.sh — optional LLM (deepeval) behavioral eval for the
# implement-spring-kotlin-core skill. The deterministic gate stays in
# run_eval.sh; this suite is network-dependent and probabilistic, so it is
# never a completion gate (see AGENTS.md §4).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLM_DIR="$SCRIPT_DIR/llm"
TEST_FILE="$LLM_DIR/test_skill_behavior.py"

# Credentials and model come from the environment only. The key value is
# never read, echoed, or persisted — only its presence is checked here.
missing=""
[ -z "${OPENAI_API_KEY:-}" ] && missing="OPENAI_API_KEY"
[ -z "${OPENAI_BASE_URL:-}" ] && missing="${missing:+$missing, }OPENAI_BASE_URL"
[ -z "${OPENAI_DEFAULT_MODEL:-}" ] && missing="${missing:+$missing, }OPENAI_DEFAULT_MODEL"
if [ -n "$missing" ]; then
  echo "ERROR: $missing must be set in the environment" >&2
  echo "       (OpenAI-compatible endpoint; values are never read or echoed)." >&2
  exit 1
fi
export OPENAI_API_KEY OPENAI_BASE_URL OPENAI_DEFAULT_MODEL

if [ ! -f "$TEST_FILE" ]; then
  echo "ERROR: missing $TEST_FILE" >&2
  exit 1
fi

VENV="$LLM_DIR/.venv"
if [ ! -x "$VENV/bin/deepeval" ]; then
  echo "[setup] creating venv at evals/llm/.venv and installing deepeval (one-time)"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check --upgrade pip
  "$VENV/bin/pip" install --quiet --disable-pip-version-check "deepeval>=2.2" pytest
fi

cd "$SCRIPT_DIR"
echo "[run] LLM eval (model: $OPENAI_DEFAULT_MODEL)"
exec "$VENV/bin/deepeval" test run "$TEST_FILE"
