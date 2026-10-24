#!/usr/bin/env bash
#
# check-commit-plan.sh — validate a multi-commit plan for a large change set.
#
# Usage:
#   bash scripts/check-commit-plan.sh "<header-1>" "<header-2>" ...
#
# Rules:
#   1. At least 1 commit in the plan.
#   2. At most MAX_COMMITS (5) commits — do not over-split.
#   3. Every header must pass check-commit-msg.sh.
#   4. No duplicate headers.
#
# Zero-MCP by design: plain bash, no servers, no state.

set -u

MAX_COMMITS=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MSG_CHECKER="$SCRIPT_DIR/check-commit-msg.sh"

if [ "$#" -eq 0 ]; then
  echo "ERROR: empty commit plan — provide at least one commit message" >&2
  exit 1
fi

if [ "$#" -gt "$MAX_COMMITS" ]; then
  echo "ERROR: plan has $# commits, max $MAX_COMMITS — merge related commits instead of splitting further" >&2
  exit 1
fi

plan=("$@")

# Every header must be a valid conventional commit.
i=0
for msg in "${plan[@]}"; do
  i=$((i + 1))
  if ! out="$("$MSG_CHECKER" "$msg" 2>&1)"; then
    echo "ERROR: commit #$i in the plan is invalid:" >&2
    echo "$out" | sed 's/^/       /' >&2
    exit 1
  fi
done

# No duplicate headers.
for ((i = 0; i < ${#plan[@]}; i++)); do
  for ((j = 0; j < i; j++)); do
    if [ "${plan[$i]}" = "${plan[$j]}" ]; then
      echo "ERROR: commits #$((j + 1)) and #$((i + 1)) are identical: ${plan[$i]}" >&2
      exit 1
    fi
  done
done

echo "PASS: Valid commit plan ($# commits, max $MAX_COMMITS)"
exit 0
