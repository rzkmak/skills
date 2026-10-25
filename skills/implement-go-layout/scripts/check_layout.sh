#!/usr/bin/env bash
#
# check_layout.sh — validate a Go + Gin project against the standard
# domain-modular layout prescribed by skills/implement-go-layout.
#
# Usage:
#   bash scripts/check_layout.sh <project-dir>
#
# Exit 0 when every check passes, exit 1 otherwise.
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
  echo "Usage: check_layout.sh <project-dir>" >&2
  exit 1
fi

PROJECT="$(resolve_path "$1")"
if [ ! -d "$PROJECT" ]; then
  echo "FAIL: project directory not found: $PROJECT" >&2
  exit 1
fi

FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# Build a comment-stripped mirror of all .go files so greps judge code,
# never comments (e.g. "// never use gin.Default()" must not be flagged).
MIRROR="$(mktemp -d)"
trap 'rm -rf "$MIRROR"' EXIT
while IFS= read -r f; do
  rel="${f#"$PROJECT"/}"
  mkdir -p "$MIRROR/$(dirname "$rel")"
  grep -v '^[[:space:]]*//' "$f" > "$MIRROR/$rel" || true
done < <(find "$PROJECT" -name '*.go' -type f)

# --- 1. go.mod at the root ---------------------------------------------------
if [ -f "$PROJECT/go.mod" ]; then
  pass "go.mod found at project root"
else
  fail "go.mod not found at project root"
fi

# --- 2. Entry point lives under cmd/ ------------------------------------------
MAIN_GO=""
for candidate in "$PROJECT"/cmd/*/main.go; do
  if [ -f "$candidate" ]; then MAIN_GO="$candidate"; break; fi
done
if [ -n "$MAIN_GO" ]; then
  pass "entry point found under cmd/ ($MAIN_GO)"
else
  fail "no cmd/*/main.go entry point found"
fi

# --- 3. main.go is a composition root only (no route registration) ------------
if [ -n "$MAIN_GO" ]; then
  MAIN_REL="${MAIN_GO#"$PROJECT"/}"
  if grep -En '\.(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|Any|Handle)\(' "$MIRROR/$MAIN_REL" >/dev/null 2>&1; then
    fail "main.go registers routes — main.go is a composition root only; move route registration into internal/ handler or routes files"
    grep -En '\.(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|Any|Handle)\(' "$MIRROR/$MAIN_REL" | sed 's/^/       /'
  else
    pass "main.go does not register routes"
  fi
fi

# --- 4. gin.Context / gin imports stay at the edge ----------------------------
GIN_FILES="$(grep -Rl --include='*.go' -e 'gin-gonic/gin' -e 'gin\.Context' "$MIRROR" 2>/dev/null || true)"
if [ -n "$GIN_FILES" ]; then
  while IFS= read -r f; do
    rel="${f#"$MIRROR"/}"
    case "$rel" in
      cmd/*|*handler*|*controller*|*middleware*|*routes*|*router*|*server*)
        : ;;
      *)
        fail "gin.Context / gin import found outside the transport layer: $rel"
        ;;
    esac
  done <<EOF
$GIN_FILES
EOF
fi
if [ "$FAILURES" -eq 0 ] && [ -n "$GIN_FILES" ]; then
  pass "gin usage confined to handler/middleware/routes/server files"
fi

# --- 5. ShouldBind* family only (no auto-aborting Bind*) ----------------------
BIND_HITS="$(grep -RnE --include='*.go' '\.(BindJSON|BindXML|BindYAML|BindQuery|Bind)\(' "$MIRROR" 2>/dev/null || true)"
if [ -n "$BIND_HITS" ]; then
  fail "auto-aborting Bind* method used — use ShouldBind* instead (Gin docs: prefer ShouldBind for error control)"
  echo "$BIND_HITS" | sed 's/^/       /'
else
  pass "no auto-aborting Bind* usage"
fi

# --- 6. gin.New() with explicit middleware chain (no gin.Default()) -----------
DEFAULT_HITS="$(grep -Rn --include='*.go' 'gin\.Default()' "$MIRROR" 2>/dev/null || true)"
if [ -n "$DEFAULT_HITS" ]; then
  fail "gin.Default() hides the middleware chain — use gin.New() plus explicit Use(...) calls"
  echo "$DEFAULT_HITS" | sed 's/^/       /'
else
  pass "no gin.Default() usage"
fi

# --- 7. No package-level mutable clients -------------------------------------
GLOBAL_HITS="$(grep -RnE --include='*.go' -e '^[[:space:]]*var[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+\*sql\.DB' -e 'http\.DefaultClient' "$MIRROR" 2>/dev/null || true)"
if [ -n "$GLOBAL_HITS" ]; then
  fail "package-level mutable client found — construct in cmd/ and inject via constructors"
  echo "$GLOBAL_HITS" | sed 's/^/       /'
else
  pass "no package-level mutable clients"
fi

# --- 8. Per-domain route registration (Register*Routes) ------------------------
# Accepts plain functions and methods with receivers, e.g.
#   func RegisterUserRoutes(rg *gin.RouterGroup)
#   func (s *Server) RegisterRoutes(rg *gin.RouterGroup)
if grep -RqE --include='*.go' 'func (\([^)]*\) )?Register[A-Za-z0-9_]*Routes\(' "$MIRROR" 2>/dev/null; then
  pass "per-domain Register*Routes functions found"
else
  fail "no Register*Routes function found — routes must be registered per domain on a gin.RouterGroup"
fi

# --- 9. Domain models carry no transport binding tags --------------------------
MODEL_HITS="$(grep -Rn --include='*model*.go' 'binding:"' "$MIRROR" 2>/dev/null || true)"
if [ -n "$MODEL_HITS" ]; then
  fail "binding: transport tags found on domain model — move validation tags to DTOs (dto.go or handler request structs)"
  echo "$MODEL_HITS" | sed 's/^/       /'
else
  pass "domain models free of binding tags"
fi

if [ "$FAILURES" -gt 0 ]; then
  echo "check_layout: $FAILURES check(s) failed" >&2
  exit 1
fi
echo "check_layout: all checks passed for $PROJECT"
exit 0
