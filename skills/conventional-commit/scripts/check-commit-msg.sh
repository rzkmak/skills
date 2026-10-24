#!/usr/bin/env bash
#
# check-commit-msg.sh — stateless Conventional Commits header validator.
#
# Usage:
#   ./skills/conventional-commit/scripts/check-commit-msg.sh "<header>"
#
# Rules:
#   1. Input must be non-empty.
#   2. Header must be at most 72 characters.
#   3. Header must match: ^(<type>)[optional (<scope>)][!]?: <lowercase description>$
#      with no trailing period, where <type> is one of:
#      feat fix docs style refactor perf test build ci chore revert
#
# Zero-MCP by design: plain bash, no servers, no state.

set -u

TYPES='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
REGEX="^(${TYPES})(\([a-z0-9_-]+\))?!?: [a-z].*[^.]$"

MSG="${1:-}"

# Rule 1: non-empty input.
if [ -z "$MSG" ]; then
  echo "ERROR: commit message is empty" >&2
  exit 1
fi

# Rule 2: header length <= 72 characters.
LEN=${#MSG}
if [ "$LEN" -gt 72 ]; then
  echo "ERROR: header is ${LEN} characters long (max 72)" >&2
  exit 1
fi

# Rule 3: Conventional Commits shape.
if ! [[ "$MSG" =~ $REGEX ]]; then
  {
    echo "ERROR: message does not match the Conventional Commits format:"
    echo "       <type>[optional scope][!]: <lowercase description, no trailing period>"
    echo "       allowed types: ${TYPES//|/, }"
  } >&2
  exit 1
fi

echo "PASS: Valid conventional commit"
exit 0
