#!/usr/bin/env bash
#
# install-commands.sh — install every skill's slash commands for your agents.
#
# One action, all commands, all agents: discovers skills/*/commands/*.md across
# the whole repo and installs them into each selected agent's commands directory.
#
# Usage:
#   ./scripts/install-commands.sh [project|global] [agents] [repo-dir]
#   ./scripts/install-commands.sh --verify [agents]
#
#   project  (default) install into the current project
#   global   install into your home directory (all projects)
#   agents   comma-separated list (default: opencode,claude-code)
#
# Agent targets:
#   opencode     project .opencode/commands/   global ~/.config/opencode/commands/
#   claude-code  project .claude/commands/     global ~/.claude/commands/
#
# Run from anywhere: when not inside a checkout, the repo is cloned to a
# temporary directory first, so this also works:
#   curl -fsSL https://raw.githubusercontent.com/rzkmak/skills/main/scripts/install-commands.sh | bash
#
# Zero-MCP by design: plain bash, no servers, no state beyond the copies made.

set -u

REPO_URL="${REPO_URL:-https://github.com/rzkmak/skills.git}"

die() { echo "ERROR: $*" >&2; exit 1; }

MODE="${1:-project}"
AGENTS="${2:-opencode,claude-code}"
EXPLICIT_DIR="${3:-}"

target_dir() {
  case "$1:$2" in
    opencode:project)    echo "$PWD/.opencode/commands"; return 0 ;;
    opencode:global)     echo "$HOME/.config/opencode/commands"; return 0 ;;
    claude-code:project) echo "$PWD/.claude/commands"; return 0 ;;
    claude-code:global)  echo "$HOME/.claude/commands"; return 0 ;;
  esac
  return 1
}

# Validate requested agents up front.
OLDIFS="$IFS"
IFS=','
for agent in $AGENTS; do
  target_dir "$agent" project >/dev/null 2>&1 || die "unknown agent '$agent' (supported: opencode, claude-code)"
done
IFS="$OLDIFS"

# ---------------------------------------------------------------- locate repo
REPO_DIR=""
if [ -n "$EXPLICIT_DIR" ]; then
  REPO_DIR="$EXPLICIT_DIR"
else
  d="$PWD"
  while [ "$d" != "/" ]; do
    if [ -f "$d/scripts/install-commands.sh" ] && [ -d "$d/skills" ]; then
      REPO_DIR="$d"
      break
    fi
    d="$(dirname "$d")"
  done
fi

TMP_DIR=""
if [ -z "$REPO_DIR" ]; then
  command -v git >/dev/null 2>&1 || die "git not found and no local checkout detected"
  TMP_DIR="$(mktemp -d)"
  git clone --quiet --depth 1 "$REPO_URL" "$TMP_DIR/repo" || { rm -rf "$TMP_DIR"; die "could not clone $REPO_URL"; }
  REPO_DIR="$TMP_DIR/repo"
fi

[ -d "$REPO_DIR/skills" ] || die "no skills/ directory under $REPO_DIR"

cleanup() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"; return 0; }
trap cleanup EXIT

# ---------------------------------------------------------------- verify mode
if [ "$MODE" = "--verify" ]; then
  status=0
  checked=0
  OLDIFS="$IFS"
  IFS=','
  for agent in $AGENTS; do
    proj_dir="$(target_dir "$agent" project)"
    for template in "$REPO_DIR"/skills/*/commands/*.md; do
      [ -f "$template" ] || continue
      name="$(basename "$template")"
      installed="$proj_dir/$name"
      if [ -f "$installed" ]; then
        checked=$((checked + 1))
        if ! diff -q "$installed" "$template" >/dev/null; then
          echo "ERROR: $installed differs from template $template" >&2
          echo "       fix with: ./scripts/install-commands.sh project $AGENTS" >&2
          status=1
        fi
      fi
    done
  done
  IFS="$OLDIFS"
  if [ "$status" -eq 0 ]; then
    echo "PASS: $checked installed command(s) in sync with templates"
  fi
  exit "$status"
fi

# ---------------------------------------------------------------- install
case "$MODE" in
  project|global) ;;
  *) die "unknown mode '$MODE' (expected: project, global, or --verify)" ;;
esac

# Command filenames must be unique repo-wide.
seen_names=""
for template in "$REPO_DIR"/skills/*/commands/*.md; do
  [ -f "$template" ] || continue
  name="$(basename "$template")"
  case "$seen_names" in
    *"|$name|"*) die "duplicate command name '$name' — command filenames must be unique repo-wide" ;;
  esac
  seen_names="$seen_names|$name|"
done

total=0
OLDIFS="$IFS"
IFS=','
for agent in $AGENTS; do
  target="$(target_dir "$agent" "$MODE")"
  count=0
  for template in "$REPO_DIR"/skills/*/commands/*.md; do
    [ -f "$template" ] || continue
    name="$(basename "$template")"
    mkdir -p "$target"
    cp "$template" "$target/$name"
    echo "[$agent] installed /${name%.md} -> $target/$name"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || die "no skills/*/commands/*.md found under $REPO_DIR"
  total=$((total + count))
done
IFS="$OLDIFS"

echo "PASS: installed $total command(s) for agent(s): $AGENTS ($MODE)"
exit 0
