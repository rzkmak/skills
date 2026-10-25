#!/usr/bin/env bash
#
# run_eval.sh — evaluation gate for the implement-spring-kotlin-core skill.
# Exits 0 only if every check passes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
SKILL_MD="$SKILL_DIR/SKILL.md"
LAYOUT_CHECKER="$SKILL_DIR/scripts/check-layout.sh"
SOURCE_CHECKER="$SKILL_DIR/scripts/check-source.sh"

# 1. Frontmatter: name must match the skill folder, description must be present.
SKILL_NAME="$(basename "$SKILL_DIR")"
front_name="$(awk '/^name:/{print $2; exit}' "$SKILL_MD")"
front_desc="$(awk '/^description:/{sub(/^description: */, ""); print; exit}' "$SKILL_MD")"

if [ "$front_name" != "$SKILL_NAME" ]; then
  echo "FAIL: SKILL.md frontmatter name is '${front_name:-<missing>}', expected '$SKILL_NAME'" >&2
  exit 1
fi
if [ -z "$front_desc" ]; then
  echo "FAIL: SKILL.md frontmatter description is missing" >&2
  exit 1
fi
echo "[OK] frontmatter: name=$SKILL_NAME, description present"

# 2. Syntax-check the runtime validators.
bash -n "$LAYOUT_CHECKER"
bash -n "$SOURCE_CHECKER"
echo "[OK] bash -n: scripts/check-layout.sh, scripts/check-source.sh"

# 3. Run the dataset judge.
python3 "$SCRIPT_DIR/judge.py"

# 4. Run filesystem directory-mode integration checks (Gradle [L3]/[L4]/[L8] + .kt tree).
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BASE_PKG="$TMP_DIR/src/main/kotlin/com/acme/order"
UNIT_PKG="$TMP_DIR/src/unitTest/kotlin/com/acme/order"
FUNC_PKG="$TMP_DIR/src/functionalTest/kotlin/com/acme/order"
mkdir -p \
  "$TMP_DIR/gradle" \
  "$BASE_PKG/configuration" \
  "$BASE_PKG/controller/request" \
  "$BASE_PKG/controller/response" \
  "$BASE_PKG/application/service" \
  "$BASE_PKG/application/transaction" \
  "$BASE_PKG/application/entity" \
  "$BASE_PKG/application/client" \
  "$BASE_PKG/application/repository/kv" \
  "$BASE_PKG/application/repository/entity" \
  "$BASE_PKG/util" \
  "$UNIT_PKG/application/service" \
  "$FUNC_PKG/controller" \
  "$TMP_DIR/src/functionalTest/resources/datasets"

cat > "$TMP_DIR/gradle/libs.versions.toml" <<'EOF'
[versions]
kotlin = "2.2.20"
spring-boot = "4.0.0"
EOF

cat > "$TMP_DIR/build.gradle.kts" <<'EOF'
java { toolchain { languageVersion.set(JavaLanguageVersion.of(25)) } }
dependencies { implementation("org.springframework.boot:spring-boot-starter-webmvc") }
EOF

cat > "$BASE_PKG/util/DateTimeUtil.kt" <<'EOF'
package com.acme.order.util

import java.time.Instant

object DateTimeUtil {
    fun now(): Instant = Instant.now()
}
EOF

cat > "$UNIT_PKG/application/service/OrderServiceUnitTest.kt" <<'EOF'
package com.acme.order.application.service

import org.junit.jupiter.api.Test

class OrderServiceUnitTest {
    @Test
    fun `unit test`() {}
}
EOF

cat > "$FUNC_PKG/controller/OrderFunctionalTest.kt" <<'EOF'
package com.acme.order.controller

import com.github.database.rider.core.api.dataset.DataSet
import com.github.database.rider.core.api.dataset.ExpectedDataSet
import com.github.database.rider.spring.api.DBRider
import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import org.wiremock.spring.EnableWireMock

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@DBRider
@EnableWireMock
class OrderFunctionalTest {
    companion object {
        @Container
        @ServiceConnection
        @JvmStatic
        val postgres = PostgreSQLContainer("postgres:17-alpine")
    }

    @Test
    @DataSet("datasets/orders.yml")
    @ExpectedDataSet("datasets/orders.yml")
    fun `e2e test`() {}
}
EOF

"$LAYOUT_CHECKER" "$TMP_DIR" >/dev/null
"$SOURCE_CHECKER" "$TMP_DIR/src" >/dev/null

# Verify [L3] catches monolithic spring-boot-starter-web on disk
cat > "$TMP_DIR/build.gradle.kts" <<'EOF'
dependencies { implementation("org.springframework.boot:spring-boot-starter-web") }
EOF
if "$LAYOUT_CHECKER" "$TMP_DIR" >/dev/null 2>&1; then
  echo "FAIL: expected check-layout.sh to reject monolithic spring-boot-starter-web" >&2
  exit 1
fi

# Verify [L4] catches Java 21 toolchain on disk
cat > "$TMP_DIR/build.gradle.kts" <<'EOF'
java { toolchain { languageVersion.set(JavaLanguageVersion.of(21)) } }
EOF
if "$LAYOUT_CHECKER" "$TMP_DIR" >/dev/null 2>&1; then
  echo "FAIL: expected check-layout.sh to reject Java 21 toolchain" >&2
  exit 1
fi
echo "[OK] directory-mode integration checks passed"

echo "[OK] $SKILL_NAME eval suite passed"
