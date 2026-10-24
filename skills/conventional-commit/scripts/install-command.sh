#!/usr/bin/env bash
#
# install-command.sh — install this skill's /commit command for OpenCode.
#
# Usage:
#   bash scripts/install-command.sh [project|global]   # default: project
#   bash scripts/install-command.sh --verify           # read-only sync check
#
# Targets:
#   project  ./.opencode/commands/commit.md            (current project)
#   global   ~/.config/opencode/commands/commit.md     (all projects)
#
# Zero-MCP by design: plain bash, no servers, no state.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
COMMAND_SRC="$SKILL_DIR/commands/commit.md"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$COMMAND_SRC" ] || die "command template not found: $COMMAND_SRC"

if [ "${1:-project}" = "--verify" ]; then
  # Read-only: if a project copy exists, it must match the shipped template.
  repo_copy="./.opencode/commands/commit.md"
  if [ -f "$repo_copy" ]; then
    if diff -q "$repo_copy" "$COMMAND_SRC" >/dev/null; then
      echo "PASS: command copies are in sync"
      exit 0
    fi
    echo "ERROR: $repo_copy differs from $COMMAND_SRC — re-run: bash scripts/install-command.sh project" >&2
    exit 1
  fi
  echo "PASS: no project command copy to verify"
  exit 0
fi

SCOPE="${1:-project}"
case "$SCOPE" in
  project) TARGET_DIR="$PWD/.opencode/commands" ;;
  global)  TARGET_DIR="$HOME/.config/opencode/commands" ;;
  *)       die "unknown scope '$SCOPE' (expected: project or global)" ;;
esac

mkdir -p "$TARGET_DIR"
cp "$COMMAND_SRC" "$TARGET_DIR/commit.md"
echo "PASS: installed /commit to $TARGET_DIR/commit.md"
exit 0
