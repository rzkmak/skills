#!/usr/bin/env bash
#
# check_snippet.sh — validate a single Go file against the layout rules
# prescribed by skills/implement-go-layout. Use it on a file the agent is
# about to write (handler, service, repository, model, router, main).
#
# Usage:
#   bash scripts/check_snippet.sh <path-to-file.go>
#
# Exit 0 when every rule passes, exit 1 otherwise.
set -u

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

resolve_path() {
  local p="$1" alt
  if [ -e "$p" ]; then
    printf '%s' "$p"
  else
    alt="$SKILL_ROOT/$p"
    if [ -e "$alt" ]; then printf '%s' "$alt"; else printf '%s' "$p"; fi
  fi
}

if [ "$#" -ne 1 ]; then
  echo "Usage: check_snippet.sh <path-to-file.go>" >&2
  exit 1
fi

FILE="$(resolve_path "$1")"
if [ ! -f "$FILE" ]; then
  echo "FAIL: file not found: $FILE" >&2
  exit 1
fi

BASE="$(basename "$FILE")"
FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# Strip whole-line comments so greps judge code, never comments
# (e.g. "// never use gin.Default()" must not be flagged).
CODE="$(mktemp)"
trap 'rm -f "$CODE"' EXIT
grep -v '^[[:space:]]*//' "$FILE" > "$CODE" || true

has_gin() { grep -Eq 'gin-gonic/gin|gin\.Context' "$CODE"; }
has_bind_family() { grep -Eq '\.(BindJSON|BindXML|BindYAML|BindQuery|Bind)\(' "$CODE"; }
has_route_registration() { grep -Eq '\.(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|Any|Handle)\(' "$CODE"; }
has_binding_tags() { grep -q 'binding:"' "$CODE"; }
has_gin_default() { grep -q 'gin\.Default()' "$CODE"; }

case "$BASE" in
  *service*.go|*usecase*.go|*repository*.go|*store*.go|*model*.go)
    if has_gin; then
      fail "$BASE: business/data layer must not reference gin.Context or import gin-gonic/gin — gin.Context stays at the edge (handler/middleware)"
    else
      pass "$BASE: no gin dependency in business/data layer"
    fi
    case "$BASE" in
      *model*.go)
        if has_binding_tags; then
          fail "$BASE: domain model carries binding: transport tags — move validation tags to DTOs (dto.go or handler request structs)"
        else
          pass "$BASE: domain model free of binding tags"
        fi
        ;;
    esac
    ;;
  *handler*.go|*controller*.go)
    if has_bind_family; then
      fail "$BASE: auto-aborting Bind* used — use ShouldBind* (Gin docs: prefer ShouldBind for custom error handling)"
    else
      pass "$BASE: binding uses ShouldBind* family"
    fi
    if has_binding_tags; then
      pass "$BASE: transport binding tags on request DTOs (allowed in handlers)"
    fi
    ;;
  main.go|main_*.go|*_main.go)
    if has_route_registration; then
      fail "main.go is a composition root only — it must not register routes; move route registration into internal/ handler or routes files"
      grep -En '\.(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|Any|Handle)\(' "$CODE" | sed 's/^/       /'
    else
      pass "main.go is a composition root only: no route registration"
    fi
    if has_gin; then
      fail "main.go should not import gin-gonic/gin directly — assemble dependencies and delegate to internal/server"
    fi
    ;;
  *router*.go|*routes*.go|*server*.go)
    if has_gin_default; then
      fail "$BASE: gin.Default() hides the middleware chain — use gin.New() plus explicit Use(...) calls"
    else
      pass "$BASE: router built on gin.New() (or no gin.Default usage)"
    fi
    ;;
  *)
    # Unknown kind: apply the universal rules only.
    if has_bind_family; then
      fail "$BASE: auto-aborting Bind* used — use ShouldBind*"
    fi
    if has_gin_default; then
      fail "$BASE: gin.Default() hides the middleware chain — use gin.New() plus explicit Use(...)"
    fi
    if [ "$FAILURES" -eq 0 ]; then
      pass "$BASE: no universal rule violations"
    fi
    ;;
esac

if [ "$FAILURES" -gt 0 ]; then
  echo "check_snippet: $FAILURES check(s) failed for $BASE" >&2
  exit 1
fi
echo "check_snippet: all checks passed for $BASE"
exit 0
