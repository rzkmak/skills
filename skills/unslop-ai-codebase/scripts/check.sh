#!/usr/bin/env bash
# check.sh — validator for unslop-ai-codebase rewrites.
#
# Usage: bash scripts/check.sh <file-path>
#
# Verifies that a de-slop rewrite of a source file:
#   1. Preserved every tooling pragma directive present in the file
#      (//nolint, //go:build, //go:generate, # noqa, # type: ignore,
#       // @ts-expect-error, /* istanbul ignore next */, etc.).
#   2. Did not alter non-comment runtime code structure: the sequence of
#      non-comment, non-blank code tokens must be unchanged versus the
#      original file (checked against <file-path>.orig if present, else
#      against the file itself, which trivially passes).
#
# Exits 0 on pass, 1 on failure with a reason on stderr.
set -u

file="${1:-}"

if [ -z "$file" ]; then
  echo "ERROR: input is empty — pass a file path" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "ERROR: file not found: $file" >&2
  exit 1
fi

PRAGMA_PATTERNS=(
  'nolint'
  'go:build'
  'go:generate'
  'noqa'
  'type: ignore'
  '@ts-expect-error'
  '@ts-ignore'
  'istanbul ignore'
  'pragma: no cover'
  'pylint: disable'
  'golangci'
  'tslint:disable'
  'eslint-disable'
  'biome-ignore'
  'rubocop:disable'
)

fail=0

# --- 1. Pragmas must survive the rewrite -------------------------------------
for pattern in "${PRAGMA_PATTERNS[@]}"; do
  orig_count="$(grep -c -F -- "$pattern" "$file" 2>/dev/null || true)"
  orig_file="$file.orig"
  if [ -f "$orig_file" ]; then
    before="$(grep -c -F -- "$pattern" "$orig_file" 2>/dev/null || true)"
    if [ "$before" -gt 0 ] && [ "$orig_count" -lt "$before" ]; then
      echo "FAIL: $file lost $((before - orig_count)) occurrence(s) of pragma '$pattern' during rewrite" >&2
      fail=1
    fi
  fi
done

# --- 2. Runtime code structure must be unchanged ------------------------------
# Strip comments and blank lines, normalize whitespace, compare token streams.
strip_code() {
  # Remove full-line and trailing // comments, # comments, and /* */ blocks,
  # then drop blank lines and squeeze whitespace.
  sed -e 's|//.*||g' -e 's|#.*||g' "$1" \
    | perl -0pe 's{/\*.*?\*/}{}gs' \
    | grep -v '^[[:space:]]*$' \
    | sed -e 's|[[:space:]]\+| |g' -e 's|^[[:space:]]*||' -e 's|[[:space:]]*$||'
}

orig_file="$file.orig"
if [ -f "$orig_file" ]; then
  a="$(strip_code "$orig_file")"
  b="$(strip_code "$file")"
  if [ "$a" != "$b" ]; then
    echo "FAIL: $file runtime code changed during rewrite (non-comment code differs from $orig_file)" >&2
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "PASS: $file — pragmas intact, runtime code unchanged"
exit 0
