#!/usr/bin/env bash
#
# check-source.sh — stateless validator for Spring Boot 4 + Kotlin 2 + Java 25 source & test files.
#
# Usage:
#   bash scripts/check-source.sh <kotlin-file-or-dir>
#   bash scripts/check-source.sh --code "<kotlin-source-code>"
#
# Enforces:
#   [S0] Package declaration must match the standard layout hierarchy
#   [S1] Jakarta EE 11 namespaces (jakarta.* instead of javax.*)
#   [S2] Jackson 3 namespaces (tools.jackson.* instead of com.fasterxml.jackson.databind.*)
#   [S3] JSpecify / Kotlin null-safety (no org.springframework.lang.Nullable/NonNull)
#   [S4] Constructor injection only (no @Autowired field/setter injection)
#   [S5] No legacy RestTemplate (use @HttpExchange + RestClient)
#   [S6] No synchronized / @Synchronized (prevents Java 25 Virtual Thread pinning)
#   [S7] No legacy java.util.Date / Calendar / SimpleDateFormat (use java.time.*)
#   [C1] controller only calls application.service and uses controller.{request,response}
#   [C2] controller.{request,response} must not be JPA entities
#   [A1] application.service must not use @Transactional or import controller.*
#   [A2] application.transaction must not import application.client.* or controller.*
#   [A3] application.entity must not use `data class` on @Entity or import web/controller
#   [A4] application.repository.kv must not use jakarta.persistence.* or @Transactional
#   [A5] application.repository.entity must not import controller.* or application.client.*
#   [U1] util must be stateless (no Spring @Component/@Service/@Repository/@Configuration/@Autowired)
#   [T1] unitTest must be pure (mocked collaborators only; no @SpringBootTest, Testcontainers, DBRider, or WireMock)
#   [T2] functionalTest must be E2E (@SpringBootTest RANDOM_PORT/DEFINED_PORT, no @MockBean/@MockitoBean/@MockkBean, @DBRider when using @DataSet/@ExpectedDataSet)

set -uo pipefail

if [ "$#" -eq 0 ] || [ -z "${1:-}" ]; then
  echo "ERROR [S0]: source input is empty. Provide a .kt file/directory path or --code \"<code>\"." >&2
  exit 1
fi

MODE="path"
INLINE_CODE=""
TARGET_PATH=""

if [ "$1" = "--code" ]; then
  MODE="code"
  shift
  INLINE_CODE="$*"
elif [ -e "$1" ]; then
  MODE="path"
  TARGET_PATH="$1"
else
  MODE="code"
  INLINE_CODE="$*"
fi

python3 - "$MODE" "$TARGET_PATH" "$INLINE_CODE" <<'PYEOF'
import pathlib
import re
import sys

mode = sys.argv[1]
target_path = sys.argv[2]
inline_code = sys.argv[3]

sources = []  # list of (label, content)

if mode == "code":
    if not inline_code.strip():
        print("ERROR [S0]: inline Kotlin code is empty.", file=sys.stderr)
        sys.exit(1)
    sources.append(("<inline>", inline_code))
else:
    p = pathlib.Path(target_path)
    if p.is_file():
        sources.append((str(p), p.read_text(encoding="utf-8")))
    elif p.is_dir():
        kt_files = sorted(
            f for f in p.rglob("*.kt")
            if "/build/" not in str(f) and "/.gradle/" not in str(f)
        )
        if not kt_files:
            print(f"ERROR [S0]: No .kt files found under '{target_path}'.", file=sys.stderr)
            sys.exit(1)
        for f in kt_files:
            sources.append((str(f), f.read_text(encoding="utf-8")))
    else:
        print(f"ERROR [S0]: Path '{target_path}' does not exist.", file=sys.stderr)
        sys.exit(1)

VALID_PACKAGE_SUFFIXES = (
    ".configuration",
    ".controller",
    ".controller.request",
    ".controller.response",
    ".application.service",
    ".application.transaction",
    ".application.entity",
    ".application.client",
    ".application.repository.kv",
    ".application.repository.entity",
    ".util",
)

def strip_comments(src: str) -> str:
    # Remove /* ... */ block comments and // ... line comments while preserving string literals
    pattern = re.compile(
        r'"(?:\\.|[^"\\])*"|/\*[\s\S]*?\*/|//[^\n]*'
    )
    return pattern.sub(lambda m: m.group(0) if m.group(0).startswith('"') else "", src)


errors = []

for label, raw_code in sources:
    code = strip_comments(raw_code)
    pkg_match = re.search(r"^\s*package\s+([a-zA-Z0-9_.]+)", code, re.MULTILINE)
    if not pkg_match:
        errors.append(f"ERROR [S0] ({label}): Missing 'package' declaration.")
        continue
    pkg = pkg_match.group(1)

    is_unit_test = (
        "/unitTest/" in label
        or bool(re.search(r"\bclass\s+\w+UnitTest\b", code))
    )
    is_functional_test = (
        "/functionalTest/" in label
        or bool(re.search(r"\bclass\s+\w+FunctionalTest\b", code))
    )
    is_test_file = is_unit_test or is_functional_test

    is_springboot_app = bool(re.search(r"@SpringBootApplication\b", code))
    if (
        not is_springboot_app
        and not is_functional_test
        and not any(pkg.endswith(sfx) for sfx in VALID_PACKAGE_SUFFIXES)
    ):
        errors.append(
            f"ERROR [S0] ({label}): Package '{pkg}' does not match any standard layout package "
            f"({', '.join(s.lstrip('.') for s in VALID_PACKAGE_SUFFIXES)})."
        )

    # [S1] Legacy javax.* imports
    if re.search(r"^\s*import\s+javax\.(persistence|validation|annotation|servlet|transaction)\.", code, re.MULTILINE):
        errors.append(
            f"ERROR [S1] ({label}): Legacy 'javax.*' import detected. Spring Boot 4 / Jakarta EE 11 requires 'jakarta.*' or 'org.jspecify.annotations.*'."
        )

    # [S2] Legacy Jackson 2 databind/module imports
    if re.search(r"^\s*import\s+com\.fasterxml\.jackson\.(databind|module|core)\.", code, re.MULTILINE):
        errors.append(
            f"ERROR [S2] ({label}): Legacy Jackson 2 import ('com.fasterxml.jackson.databind/module/core') detected. Spring Boot 4 uses Jackson 3 ('tools.jackson.*')."
        )

    # [S3] Legacy Spring Nullable/NonNull annotations
    if re.search(r"^\s*import\s+org\.springframework\.lang\.(Nullable|NonNull|NonNullApi|NonNullFields)\b", code, re.MULTILINE):
        errors.append(
            f"ERROR [S3] ({label}): Deprecated 'org.springframework.lang' nullability annotation detected. Use Kotlin native nullable types ('?') or 'org.jspecify.annotations.*'."
        )

    # [S4] Field/setter @Autowired injection
    if re.search(r"@Autowired\s+(lateinit\s+var|var|val|private\s+var|private\s+lateinit\s+var)\b", code):
        errors.append(
            f"ERROR [S4] ({label}): Field/property '@Autowired' injection is forbidden. Use primary constructor injection."
        )

    # [S5] Legacy RestTemplate
    if re.search(r"\bRestTemplate\b", code):
        errors.append(
            f"ERROR [S5] ({label}): Legacy 'RestTemplate' is forbidden. Use declarative '@HttpExchange' interfaces backed by 'RestClient'."
        )

    # [S6] Virtual Thread pinning via synchronized / @Synchronized
    if re.search(r"@Synchronized\b|\bsynchronized\s*\(", code):
        errors.append(
            f"ERROR [S6] ({label}): 'synchronized' / '@Synchronized' is forbidden as it pins Java 25 Virtual Threads. Use 'ReentrantLock' instead."
        )

    # [S7] Legacy Date / Calendar / SimpleDateFormat
    if re.search(r"^\s*import\s+java\.(util\.(Date|Calendar)|text\.SimpleDateFormat)\b", code, re.MULTILINE):
        errors.append(
            f"ERROR [S7] ({label}): Legacy 'java.util.Date/Calendar' or 'SimpleDateFormat' is forbidden. Use 'java.time.*' (Instant, OffsetDateTime, LocalDate, Clock)."
        )

    # [T1] unitTest rules
    if is_unit_test:
        if re.search(
            r"@(SpringBootTest|DataJpaTest|WebMvcTest|Testcontainers|Container|ServiceConnection|DBRider|DataSet|ExpectedDataSet|EnableWireMock)\b|"
            r"^\s*import\s+(org\.testcontainers\.|com\.github\.database\.rider\.|org\.wiremock\.|com\.github\.tomakehurst\.wiremock\.)",
            code,
            re.MULTILINE,
        ):
            errors.append(
                f"ERROR [T1] ({label}): 'unitTest' must be a pure unit test with mocked dependencies only. "
                "Forbidden @SpringBootTest / Testcontainers / Database Rider / WireMock usage detected."
            )

    # [T2] functionalTest rules
    if is_functional_test:
        if not re.search(r"@SpringBootTest\b", code) or not re.search(r"RANDOM_PORT|DEFINED_PORT", code):
            errors.append(
                f"ERROR [T2] ({label}): 'functionalTest' must be an E2E API test annotated with '@SpringBootTest(webEnvironment = ...RANDOM_PORT)'."
            )
        if re.search(r"@(MockBean|MockitoBean|MockkBean)\b", code):
            errors.append(
                f"ERROR [T2] ({label}): '@MockBean/@MockitoBean/@MockkBean' is forbidden in 'functionalTest'. "
                "Use real internal beans, Dockerized persistence (Testcontainers/composeUp), and WireMock for external APIs."
            )
        if re.search(r"@(DataSet|ExpectedDataSet)\b", code) and not re.search(r"@DBRider\b", code):
            errors.append(
                f"ERROR [T2] ({label}): '@DataSet/@ExpectedDataSet' in 'functionalTest' requires '@DBRider' annotation."
            )

    # Production package-specific architectural boundary rules (skip for test files)
    if is_test_file:
        continue

    if pkg.endswith(".controller"):
        if re.search(r"^\s*import\s+[a-zA-Z0-9_.]+\.application\.(transaction|repository|client|entity)\.", code, re.MULTILINE):
            errors.append(
                f"ERROR [C1] ({label}): Controller in '{pkg}' must only depend on 'application.service' and 'controller.request'/'controller.response' (forbidden import from application.transaction/repository/client/entity)."
            )
        if re.search(r"@Transactional\b", code):
            errors.append(
                f"ERROR [C1] ({label}): '@Transactional' is forbidden in controller '{pkg}'. Delegate to 'application.service' -> 'application.transaction'."
            )

    elif pkg.endswith(".controller.request") or pkg.endswith(".controller.response"):
        if re.search(r"^\s*import\s+jakarta\.persistence\.|@Entity\b", code, re.MULTILINE):
            errors.append(
                f"ERROR [C2] ({label}): HTTP DTO in '{pkg}' must not use JPA '@Entity' or 'jakarta.persistence.*'."
            )
        if pkg.endswith(".controller.request") and re.search(r"^\s*import\s+[a-zA-Z0-9_.]+\.application\.entity\.", code, re.MULTILINE):
            errors.append(
                f"ERROR [C2] ({label}): Request DTO in '{pkg}' must not import 'application.entity.*'."
            )

    elif pkg.endswith(".application.service"):
        if re.search(r"@Transactional\b|^\s*import\s+org\.springframework\.transaction\.annotation\.Transactional\b", code, re.MULTILINE):
            errors.append(
                f"ERROR [A1] ({label}): '@Transactional' is forbidden in '{pkg}'. Isolate DB transactions in 'application.transaction' so Virtual Threads do not hold JDBC connections during client/KV calls."
            )
        if re.search(r"^\s*import\s+[a-zA-Z0-9_.]+\.controller\b", code, re.MULTILINE):
            errors.append(
                f"ERROR [A1] ({label}): Service in '{pkg}' must not import 'controller.*' HTTP DTOs or controllers."
            )

    elif pkg.endswith(".application.transaction"):
        if re.search(r"^\s*import\s+[a-zA-Z0-9_.]+\.application\.client\.", code, re.MULTILINE):
            errors.append(
                f"ERROR [A2] ({label}): Transaction component in '{pkg}' must not import 'application.client.*'. Never make outbound HTTP calls inside an active DB transaction."
            )
        if re.search(r"^\s*import\s+[a-zA-Z0-9_.]+\.controller\b", code, re.MULTILINE):
            errors.append(
                f"ERROR [A2] ({label}): Transaction component in '{pkg}' must not import 'controller.*'."
            )

    elif pkg.endswith(".application.entity"):
        if re.search(r"@Entity\b", code) and re.search(r"\bdata\s+class\b", code):
            errors.append(
                f"ERROR [A3] ({label}): JPA '@Entity' in '{pkg}' must not be a 'data class'. Use a regular 'class' with 'kotlin(\"plugin.jpa\")' and ID-based equals/hashCode."
            )
        if re.search(r"^\s*import\s+([a-zA-Z0-9_.]+\.controller\b|org\.springframework\.web\.)", code, re.MULTILINE):
            errors.append(
                f"ERROR [A3] ({label}): Entity in '{pkg}' must not import 'controller.*' or 'org.springframework.web.*'."
            )

    elif pkg.endswith(".application.repository.kv"):
        if re.search(r"^\s*import\s+jakarta\.persistence\.|@Transactional\b", code, re.MULTILINE):
            errors.append(
                f"ERROR [A4] ({label}): Key-Value repository in '{pkg}' must not use 'jakarta.persistence.*' or '@Transactional'."
            )

    elif pkg.endswith(".application.repository.entity"):
        if re.search(r"^\s*import\s+[a-zA-Z0-9_.]+\.(controller\b|application\.client\.)", code, re.MULTILINE):
            errors.append(
                f"ERROR [A5] ({label}): Entity repository in '{pkg}' must not import 'controller.*' or 'application.client.*'."
            )

    elif pkg.endswith(".util"):
        if re.search(r"@(Component|Service|Repository|Controller|RestController|Configuration|Autowired)\b", code):
            errors.append(
                f"ERROR [U1] ({label}): Utility in '{pkg}' must be pure and stateless (no Spring '@Component/@Service/@Repository/@Configuration/@Autowired' annotations)."
            )

if errors:
    for err in errors:
        print(err, file=sys.stderr)
    sys.exit(1)

print(f"PASS: Valid Spring Boot 4 + Kotlin 2 source ({len(sources)} source item(s) verified)")
sys.exit(0)
PYEOF
