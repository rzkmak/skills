#!/usr/bin/env bash
#
# check-layout.sh — stateless validator for Spring Boot 4 + Kotlin 2 project & package layout.
#
# Usage:
#   bash scripts/check-layout.sh <project-or-module-dir>
#   bash scripts/check-layout.sh --paths "<space-or-newline-separated-paths>"
#
# Enforces:
#   [L1] No Gradle buildSrc/ directory (use build-logic/ composite build)
#   [L2] Multi-module projects require build-logic/ and gradle/libs.versions.toml
#   [L3] No monolithic spring-boot-starter-web (use spring-boot-starter-webmvc)
#   [L4] Java 25 target (JavaLanguageVersion.of(25) / JvmTarget.JVM_25)
#   [L5] Top-level base-package folders restricted to: configuration, controller, application, util
#   [L6] Strict sub-package hierarchy (controller/{request,response}, application/{service,transaction,entity,client,repository/{kv,entity}})
#   [L7] All 10 standard packages present in each module's main base package
#   [L8] Three mandatory source sets (src/main, src/unitTest, src/functionalTest); src/test is forbidden

set -uo pipefail

if [ "$#" -eq 0 ] || [ -z "${1:-}" ]; then
  echo "ERROR [L0]: layout input is empty. Provide a directory path or --paths \"<paths>\"." >&2
  exit 1
fi

MODE="dir"
TARGET_DIR=""
RAW_PATHS=""

if [ "$1" = "--paths" ]; then
  MODE="paths"
  shift
  RAW_PATHS="$*"
elif [ -d "$1" ]; then
  MODE="dir"
  TARGET_DIR="$1"
else
  MODE="paths"
  RAW_PATHS="$*"
fi

if [ "$MODE" = "dir" ]; then
  while IFS= read -r -d '' build_file; do
    if grep -Eq 'spring-boot-starter-web(["'\'')]|$)' "$build_file"; then
      echo "ERROR [L3]: Monolithic 'spring-boot-starter-web' found in '$build_file'. Use modular 'spring-boot-starter-webmvc' in Spring Boot 4." >&2
      exit 1
    fi
    if grep -Eq 'JavaLanguageVersion\.of\((17|21)\)|JVM_(17|21)' "$build_file"; then
      echo "ERROR [L4]: Non-Java-25 target found in '$build_file'. Target Java 25 (JavaLanguageVersion.of(25) / JvmTarget.JVM_25)." >&2
      exit 1
    fi
  done < <(find "$TARGET_DIR" \( -name "build.gradle.kts" -o -name "libs.versions.toml" \) -not -path "*/.git/*" -not -path "*/.gradle/*" -not -path "*/build/*" -print0 2>/dev/null)

  RAW_PATHS="$(
    cd "$TARGET_DIR" && find . \
      -not -path "." \
      -not -path "./.git*" \
      -not -path "./.gradle*" \
      -not -path "*/build/*" \
      | sed 's|^\./||'
  )"
fi

if [ -z "$RAW_PATHS" ]; then
  echo "ERROR [L0]: No paths found to validate." >&2
  exit 1
fi

python3 - "$RAW_PATHS" <<'PYEOF'
import re
import sys

raw = sys.argv[1]
paths = [p.strip().strip("/") for p in re.split(r"[\s,]+", raw) if p.strip().strip("/")]

if not paths:
    print("ERROR [L0]: No valid paths provided.", file=sys.stderr)
    sys.exit(1)

errors = []

# [L1] Forbid buildSrc
for p in paths:
    if p == "buildSrc" or p.startswith("buildSrc/") or "/buildSrc/" in p or p.endswith("/buildSrc"):
        errors.append(
            "ERROR [L1]: 'buildSrc' directory is forbidden. Use an included composite build at 'build-logic/' with 'gradle/libs.versions.toml'."
        )
        break

# [L2] Multi-module check (when modules/ or apps/ is at root)
has_multi_module = any(p.startswith("modules/") or p.startswith("apps/") for p in paths)
if has_multi_module:
    has_version_catalog = any(p == "gradle/libs.versions.toml" for p in paths)
    has_build_logic = any(p == "build-logic" or p.startswith("build-logic/") for p in paths)
    if not has_version_catalog:
        errors.append(
            "ERROR [L2]: Multi-module project is missing 'gradle/libs.versions.toml'."
        )
    if not has_build_logic:
        errors.append(
            "ERROR [L2]: Multi-module project is missing 'build-logic/' composite build directory."
        )

# [L8] Source set separation: forbid src/test, require src/main, src/unitTest, src/functionalTest
for p in paths:
    if p == "src/test" or p.startswith("src/test/") or "/src/test/" in p or p.endswith("/src/test"):
        errors.append(
            "ERROR [L8]: Legacy 'src/test/' directory is forbidden. Separate tests into 'src/unitTest/' and 'src/functionalTest/'."
        )
        break

# Identify module roots that contain src/main (excluding build-logic)
module_roots = set()
for p in paths:
    if p.startswith("build-logic/"):
        continue
    if p == "src/main" or p.startswith("src/main/"):
        module_roots.add("")
    elif "/src/main/" in p or p.endswith("/src/main"):
        mod_root = p.split("/src/main")[0]
        module_roots.add(mod_root)

for mod in sorted(module_roots):
    mod_prefix = f"{mod}/" if mod else ""
    missing_sourcesets = []
    for ss in ("src/main", "src/unitTest", "src/functionalTest"):
        target = f"{mod_prefix}{ss}"
        if not any(p == target or p.startswith(target + "/") for p in paths):
            missing_sourcesets.append(ss)
    if missing_sourcesets:
        errors.append(
            f"ERROR [L8]: Module '{mod or '<root>'}' must define all three source sets (src/main, src/unitTest, src/functionalTest); missing: {', '.join(missing_sourcesets)}"
        )

ANCHORS = {"configuration", "controller", "application", "util"}
MISPLACED_ANCHORS = {
    "service",
    "services",
    "transaction",
    "transactions",
    "entity",
    "entities",
    "domain",
    "model",
    "models",
    "client",
    "clients",
    "repository",
    "repositories",
    "dto",
    "dtos",
    "request",
    "response",
    "infrastructure",
    "adapter",
    "adapters",
}

# Discover main base package roots (excluding build-logic, unitTest, functionalTest)
main_paths = [
    p for p in paths
    if not p.startswith("build-logic/")
    and "/src/unitTest/" not in f"/{p}/"
    and "/src/functionalTest/" not in f"/{p}/"
]

base_roots = set()
for p in main_paths:
    parts = p.split("/")
    for idx, seg in enumerate(parts):
        if seg in ANCHORS:
            prefix = "/".join(parts[:idx])
            base_roots.add(prefix)
            break

if not base_roots:
    for p in main_paths:
        parts = p.split("/")
        for idx, seg in enumerate(parts):
            if seg in MISPLACED_ANCHORS and idx >= 1:
                prefix = "/".join(parts[:idx])
                base_roots.add(prefix)
                break

if not base_roots:
    errors.append(
        "ERROR [L7]: Could not find standard package layout (configuration, controller, application, util) in main sources."
    )

REQUIRED_SUBPATHS = [
    "configuration",
    "controller/request",
    "controller/response",
    "application/service",
    "application/transaction",
    "application/entity",
    "application/client",
    "application/repository/kv",
    "application/repository/entity",
    "util",
]

ALLOWED_APPLICATION_CHILDREN = {"service", "transaction", "entity", "client", "repository"}
ALLOWED_CONTROLLER_CHILDREN = {"request", "response"}
ALLOWED_REPOSITORY_CHILDREN = {"kv", "entity"}

for base in sorted(base_roots):
    prefix = f"{base}/" if base else ""
    rel_paths = []
    for p in main_paths:
        if base == "":
            rel_paths.append(p)
        elif p.startswith(prefix):
            rel_paths.append(p[len(prefix):])

    # [L5] Check immediate children under base package
    for rp in rel_paths:
        parts = rp.split("/")
        top = parts[0]
        if len(parts) == 1 and top.endswith(".kt"):
            continue
        if top not in ANCHORS:
            errors.append(
                f"ERROR [L5]: Forbidden top-level package '{prefix}{top}'. Allowed packages under '{base or '<root>'}' are: configuration, controller, application, util."
            )

    # [L6] Check sub-packages under controller/ and application/
    for rp in rel_paths:
        parts = rp.split("/")
        if parts[0] == "controller" and len(parts) >= 2:
            second = parts[1]
            if not second.endswith(".kt") and second not in ALLOWED_CONTROLLER_CHILDREN:
                errors.append(
                    f"ERROR [L6]: Forbidden package '{prefix}controller/{second}'. Only 'controller/request' and 'controller/response' are allowed under 'controller/'."
                )
        elif parts[0] == "application" and len(parts) >= 2:
            second = parts[1]
            if second.endswith(".kt"):
                errors.append(
                    f"ERROR [L6]: File '{prefix}{rp}' cannot be placed directly in 'application/'. Place it in service, transaction, entity, client, or repository/{{kv,entity}}."
                )
            elif second not in ALLOWED_APPLICATION_CHILDREN:
                errors.append(
                    f"ERROR [L6]: Forbidden package '{prefix}application/{second}'. Allowed packages under 'application/' are: service, transaction, entity, client, repository."
                )
            elif second == "repository" and len(parts) >= 3:
                third = parts[2]
                if third.endswith(".kt"):
                    errors.append(
                        f"ERROR [L6]: Repository file '{prefix}{rp}' must be placed under 'application/repository/kv/' or 'application/repository/entity/', not directly in 'application/repository/'."
                    )
                elif third not in ALLOWED_REPOSITORY_CHILDREN:
                    errors.append(
                        f"ERROR [L6]: Forbidden package '{prefix}application/repository/{third}'. Only 'kv' and 'entity' are allowed under 'application/repository/'."
                    )

    # [L7] Check all 10 required sub-packages exist under base
    missing = []
    for req in REQUIRED_SUBPATHS:
        found = any(rp == req or rp.startswith(req + "/") for rp in rel_paths)
        if not found:
            missing.append(req)
    if missing:
        errors.append(
            f"ERROR [L7]: Base package '{base or '<root>'}' is missing required standard package(s): {', '.join(missing)}"
        )

if errors:
    seen = set()
    for err in errors:
        if err not in seen:
            seen.add(err)
            print(err, file=sys.stderr)
    sys.exit(1)

print(f"PASS: Valid Spring Boot 4 + Kotlin 2 layout ({len(base_roots)} module base package(s) verified)")
sys.exit(0)
PYEOF
