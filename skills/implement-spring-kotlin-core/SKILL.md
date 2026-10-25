---
name: implement-spring-kotlin-core
description: Use when scaffolding, structuring, implementing, testing, reviewing, or refactoring Spring Boot 4 and Kotlin 2 backend applications targeting Java 25 with Spring MVC, Virtual Threads, and JPA. Enforces the standard large-scale package layout (configuration, controller/request, controller/response, application/service, application/transaction, application/entity, application/client, application/repository/kv, application/repository/entity, util), three source sets (main, unitTest, functionalTest), Docker Compose (composeUp/composeDown), Testcontainers, WireMock, Database Rider, and strict transactional boundaries.
metadata:
  version: "0.1.0"
---
# Implement Spring Kotlin Core Skill

Standardizes large-scale backend applications built on **Spring Boot 4 (Spring Framework 7 / Jakarta EE 11)**, **Kotlin 2.2+**, and **Java 25** using **Spring MVC + Virtual Threads + JPA (Hibernate 7)**.

For complete code templates, Gradle `jvm-test-suite` + `docker-compose` configurations, and `unitTest` / `functionalTest` examples, read `references/architecture-and-examples.md`.

---

## 1. Technology & Build Baseline

1. **Java 25 & Kotlin 2.2+ Toolchain:**
   - Configure `JavaLanguageVersion.of(25)` and `JvmTarget.JVM_25`.
   - Enable compiler flags: `-Xjsr305=strict`, `-Xannotation-default-target=param-property`, and `-Xwhen-expressions=indy`.
   - Apply `kotlin("plugin.spring")` and `kotlin("plugin.jpa")` so `@Configuration`, `@Service`, `@Transactional`, and `@Entity` classes work without manual `open` or no-arg boilerplate.
2. **Spring Boot 4 Modular Starters:**
   - Use `spring-boot-starter-webmvc` (never legacy monolithic `spring-boot-starter-web`).
   - Use `spring-boot-starter-data-jpa` and `spring-boot-starter-restclient`.
   - Use modular test starters (`spring-boot-starter-webmvc-test`, `spring-boot-starter-restclient-test`, `spring-boot-testcontainers`).
3. **Virtual Threads Enabled:**
   - Set `spring.threads.virtual.enabled=true` and `spring.jpa.open-in-view=false` in `application.yml`.
   - Never use `synchronized` blocks or `@Synchronized` (prevents carrier thread pinning on Java 25); use `ReentrantLock` when explicit locking is needed.
4. **Docker & Gradle Lifecycle (`composeUp` / `composeDown` + Testcontainers):**
   - Configure `com.avast.gradle.docker-compose` in Gradle to provide `./gradlew composeUp` and `./gradlew composeDown` tasks backed by `compose.yaml` / `docker-compose.yml`, and wire `dockerCompose.isRequiredBy(tasks.named("functionalTest"))`.
   - Prefer **Testcontainers** (`org.springframework.boot:spring-boot-testcontainers`, `@Testcontainers`, `@ServiceConnection`) whenever possible for self-contained Dockerized persistence in `functionalTest`.
5. **Single-Module & Multi-Module Gradle Topology:**
   - Centralize all versions in `gradle/libs.versions.toml`.
   - **Single-Module:** Standard root `build.gradle.kts` + `compose.yaml` + `src/{main,unitTest,functionalTest}/...`.
   - **Multi-Module:** Use an included composite build at `build-logic/` (`includeBuild("build-logic")` in `settings.gradle.kts`) for shared convention plugins. **Never use `buildSrc/`.**

---

## 2. Source Sets & Standard Package Layout

### 2.1 Three Mandatory Source Sets (`main`, `unitTest`, `functionalTest`)
Every module MUST split its sources into three explicit source sets (configured via Gradle `jvm-test-suite` / `sourceSets`). **Never use the legacy generic `src/test/` directory.**

```text
<module-root>/
├── compose.yaml                                    # Docker dependencies for ./gradlew composeUp / composeDown
└── src/
    ├── main/
    │   ├── kotlin/<base-package>/...               # Production code (10 standard packages below)
    │   └── resources/application.yml
    ├── unitTest/
    │   └── kotlin/<base-package>/...               # Pure unit tests (all dependencies mocked per layer)
    └── functionalTest/
        ├── kotlin/<base-package>/...               # E2E internal API tests (real API + Docker DB + WireMock + DBRider)
        └── resources/
            ├── application-functional.yml
            └── datasets/                           # Database Rider YAML datasets (@DataSet / @ExpectedDataSet)
```

### 2.2 Production Package Hierarchy (`src/main/kotlin/<base-package>/`)
Every deployable application module or domain module MUST organize `src/main/kotlin/<base-package>` (e.g., `com.acme.order`) using this exact package hierarchy:

```text
<base-package>/
├── configuration/              # @Configuration, @ConfigurationProperties, BeanRegistrarDsl
├── controller/                 # @RestController HTTP endpoints (Spring MVC, API versioning, ProblemDetail)
│   ├── request/                # Inbound HTTP request DTOs (immutable data classes + jakarta.validation)
│   └── response/               # Outbound HTTP response DTOs (immutable data classes)
├── application/                # Core business, orchestration, external integration, and persistence
│   ├── service/                # Business orchestration (@Service); NO @Transactional allowed here
│   ├── transaction/            # Explicit @Transactional DB boundary components
│   ├── entity/                 # JPA @Entity classes (standard class, NEVER data class)
│   ├── client/                 # Outbound HTTP clients (@HttpExchange + RestClient, @Retryable)
│   └── repository/             # Data access layer split by storage semantics
│       ├── kv/                 # Key-Value / cache repositories (Redis, Valkey, Caffeine)
│       └── entity/             # Relational JPA repositories (JpaRepository interfaces)
└── util/                       # Pure, stateless utilities (java.time helpers, extensions; NO Spring beans)
```

Do NOT create top-level `service/`, `repository/`, `entity/`, `client/`, `dto/`, or `model/` packages outside their designated parent packages above. Do NOT place `.kt` files directly inside `application/repository/` without putting them under `kv/` or `entity/`.

---

## 3. Layer Responsibilities & Dependency Rules

1. **`configuration` (`<base>.configuration`)**
   - Houses `@Configuration`, immutable `@ConfigurationProperties` `data class` definitions, and Spring 7 `BeanRegistrarDsl` registrations.
   - Wires `RestClient` / `HttpServiceProxyFactory` for `@HttpExchange` clients, Jackson 3 `JsonMapper` customizations, and infrastructure beans.
2. **`controller` (`<base>.controller`, `.request`, `.response`)**
   - `@RestController` classes depend ONLY on `application.service` and `controller.request` / `controller.response`.
   - **Forbidden in `controller`:** Direct imports of `application.transaction`, `application.repository.*`, `application.client`, or `application.entity`, and `@Transactional`.
   - **`controller.request`:** Immutable `data class` payloads validated with `jakarta.validation.constraints.*`.
   - **`controller.response`:** Immutable `data class` payloads. Never expose `application.entity` classes directly in HTTP responses.
3. **`application.service` (`<base>.application.service`)**
   - Orchestrates business workflows across `application.client`, `application.repository.kv`, and `application.transaction`.
   - **Forbidden in `application.service`:** `@Transactional` and `controller.*` imports.
   - *Why:* Under Virtual Threads, network I/O (`client`, `repository.kv`) is cheap, but JDBC connections (HikariCP) are finite. Keeping `@Transactional` out of `application.service` prevents holding DB connections open during remote HTTP or KV calls and eliminates Spring AOP self-invocation bugs.
4. **`application.transaction` (`<base>.application.transaction`)**
   - Dedicated components annotated with `@Transactional` (or `@Transactional(readOnly = true)`) that execute atomic database reads/writes via `application.repository.entity` and `application.entity`.
   - **Forbidden in `application.transaction`:** Importing `application.client.*` or `controller.*` (never perform external HTTP calls inside an active DB transaction).
5. **`application.entity` (`<base>.application.entity`)**
   - Jakarta Persistence (`jakarta.persistence.*`) `@Entity` classes.
   - Must be regular Kotlin `class` declarations (relying on `kotlin("plugin.jpa")`), overriding `equals`/`hashCode` by stable identifier only.
   - **Forbidden in `application.entity`:** `data class` on `@Entity`, `controller.*` imports, and `org.springframework.web.*` imports.
6. **`application.client` (`<base>.application.client`)**
   - Outbound HTTP integrations using Spring 7 declarative `@HttpExchange` interfaces (`@GetExchange`, `@PostExchange`, etc.) backed by `RestClient`.
   - Use Spring Framework 7 native resilience annotations (`@Retryable`, `@ConcurrencyLimit`).
   - **Forbidden:** Legacy `RestTemplate`.
7. **`application.repository.kv` (`<base>.application.repository.kv`)**
   - Key-Value and cache access (Redis, Valkey, in-memory caches) with explicit TTLs and Jackson 3 (`tools.jackson.*`) serialization.
   - **Forbidden in `application.repository.kv`:** `jakarta.persistence.*` and `@Transactional`.
8. **`application.repository.entity` (`<base>.application.repository.entity`)**
   - Spring Data JPA repositories (`JpaRepository<Entity, ID>`) and custom relational queries operating on `application.entity`.
   - **Forbidden in `application.repository.entity`:** `controller.*` and `application.client.*` imports.
9. **`util` (`<base>.util`)**
   - Pure, stateless helper functions, extension functions, and `object` utilities (e.g., `java.time.Instant` / `OffsetDateTime` / `Clock` utilities).
   - **Forbidden in `util`:** Spring stereotypes (`@Component`, `@Service`, `@Repository`, `@Configuration`, `@RestController`, `@Autowired`) and legacy `java.util.Date` / `Calendar` / `SimpleDateFormat`.

---

## 4. Two-Layer Testing Architecture (`unitTest` vs `functionalTest`)

### 4.1 `unitTest` (`src/unitTest/kotlin/<base-package>/...`)
- **Purpose:** Fast, isolated pure unit tests for every layer (`controller`, `application.service`, `application.transaction`, `application.repository.*`, `util`).
- **Mocking:** Mock **all** collaborators for the class under test using **MockK** (`io.mockk.mockk`, `every`, `verify`, `@MockK`, `@InjectMockKs`).
- **Naming:** Suffix test classes with `*UnitTest` (e.g., `OrderServiceUnitTest.kt`).
- **Forbidden in `unitTest`:** `@SpringBootTest`, `@DataJpaTest`, `@WebMvcTest`, `@Testcontainers`, `@Container`, `@ServiceConnection`, `@DBRider`, `@DataSet`, `@ExpectedDataSet`, and `WireMock`. Never boot a Spring context or Docker container in `unitTest`.

### 4.2 `functionalTest` (`src/functionalTest/kotlin/<base-package>/...`)
- **Purpose:** End-to-end internal API tests (`*FunctionalTest.kt`) that boot the full Spring context (`@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)`) and invoke the real HTTP endpoints (e.g., via `RestTestClient` / `TestRestTemplate`).
- **Dockerized Persistence:**
  - Use **Testcontainers** (`@Testcontainers`, `@Container`, `@ServiceConnection`) whenever possible for PostgreSQL/MySQL/Redis containers, alongside Gradle `./gradlew composeUp` and `./gradlew composeDown` (`com.avast.gradle.docker-compose`).
- **External API Mocking with WireMock:**
  - Stub all external HTTP dependencies (`application.client`) at the network protocol level using **WireMock** (`org.wiremock.spring.EnableWireMock` / `@ConfigureWireMock` or `WireMockServer` / `WireMockContainer`).
  - **Forbidden in `functionalTest`:** Replacing internal beans or `application.client` with `@MockitoBean`, `@MockBean`, or `@MockkBean`.
- **Database State Verification with Database Rider (when JPA is tested):**
  - Annotate JPA-backed functional tests with `@DBRider` (`com.github.database.rider.spring.api.DBRider` or `com.github.database.rider.junit5.api.DBRider`).
  - Seed initial relational state with `@DataSet("datasets/...")` and assert post-request database rows with `@ExpectedDataSet("datasets/...")` stored under `src/functionalTest/resources/datasets/`.

---

## 5. Anti-Patterns Checklist (Spring Boot 4 + Kotlin 2)

| Anti-Pattern (Forbidden) | Required Standard |
| :--- | :--- |
| Using generic `src/test/` directory | Split into `src/unitTest/` and `src/functionalTest/` |
| `@SpringBootTest` or containers inside `src/unitTest/` | Pure unit tests in `src/unitTest/` with all collaborators mocked via MockK |
| `@MockBean` / `@MockkBean` in `src/functionalTest/` | Real internal beans + Testcontainers/Docker DB + **WireMock** for external HTTP APIs |
| Manual SQL setup/teardown in JPA `functionalTest` | Use **Database Rider** (`@DBRider`, `@DataSet`, `@ExpectedDataSet`) |
| `@Transactional` in `application.service` or `controller` | Isolate `@Transactional` strictly inside `application.transaction` |
| Calling `application.client` inside `application.transaction` | Perform HTTP client calls in `application.service` outside the DB transaction |
| `@Entity data class OrderEntity(...)` | Regular `class OrderEntity(...)` in `application.entity` with `kotlin("plugin.jpa")` |
| Returning `application.entity` from `@RestController` | Map to `controller.response.*Response` `data class` |
| Uncategorized `application/repository/OrderRepo.kt` | Place under `application/repository/entity/` or `application/repository/kv/` |
| `import javax.persistence.*` / `javax.validation.*` | `import jakarta.persistence.*` / `jakarta.validation.*` (Jakarta EE 11) |
| `import com.fasterxml.jackson.databind.*` | `import tools.jackson.databind.*` (Jackson 3 in Spring Boot 4) |
| `import org.springframework.lang.Nullable` | Kotlin native `T?` and `org.jspecify.annotations.Nullable` |
| `@Autowired lateinit var` field injection | Primary constructor injection (`class FooService(private val bar: Bar)`) |
| `RestTemplate` | `@HttpExchange` interface + `RestClient` |
| `synchronized(...)` or `@Synchronized` | `ReentrantLock` (prevents Java 25 Virtual Thread pinning) |
| `java.util.Date` / `SimpleDateFormat` | `java.time.Instant`, `OffsetDateTime`, `DateTimeFormatter`, `Clock` |
| Gradle `buildSrc/` directory | `build-logic/` composite build + `gradle/libs.versions.toml` |
| Monolithic `spring-boot-starter-web` | Modular `spring-boot-starter-webmvc` + `spring-boot-starter-restclient` |

---

## 6. Mandatory Verification Step

Before completing any task that creates, modifies, or reviews a Spring Boot + Kotlin project or source file, you MUST validate both the layout and the Kotlin sources using the bundled scripts (run from this skill's directory; paths are relative to the skill root):

```bash
# 1. Validate project or module directory layout (or pass --paths "<space-separated-paths>")
bash scripts/check-layout.sh /path/to/project-or-module

# 2. Validate Kotlin source & test files (main, unitTest, functionalTest)
bash scripts/check-source.sh /path/to/src
```

### Retry Limit
If a script exits with a non-zero code, read `stderr`, fix every reported violation (`[L*]` layout rules or `[S*]`/`[C*]`/`[A*]`/`[U*]`/`[T*]` source & test rules), and re-run. Retry at most 5 times — do not loop forever.

If verification still fails after 5 retries, stop retrying and rely on your own judgment:
- If you are confident the code or layout is valid for an intentional edge case and the validator is too strict, proceed and explain your reasoning clearly to the user.
- If you are not confident, ask the user how to proceed instead of guessing.
