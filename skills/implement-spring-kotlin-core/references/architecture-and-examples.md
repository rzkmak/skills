# Spring Boot 4 + Kotlin 2 + Java 25 Reference Architecture & Examples

This reference accompanies `SKILL.md` with production templates for single-module and multi-module Gradle setups, Docker Compose (`composeUp` / `composeDown`), `unitTest` / `functionalTest` source sets, and every package in the standard layout.

---

## 1. Gradle Configuration (`main`, `unitTest`, `functionalTest` + Docker)

### `gradle/libs.versions.toml`
```toml
[versions]
kotlin = "2.2.20"
spring-boot = "4.0.0"
spring-dependency-management = "1.1.7"
docker-compose-plugin = "0.17.12"
database-rider = "1.44.0"
wiremock-spring-boot = "3.6.0"
mockk = "1.13.16"
java = "25"

[libraries]
spring-boot-starter-webmvc = { module = "org.springframework.boot:spring-boot-starter-webmvc" }
spring-boot-starter-data-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-starter-restclient = { module = "org.springframework.boot:spring-boot-starter-restclient" }
spring-boot-starter-validation = { module = "org.springframework.boot:spring-boot-starter-validation" }
spring-boot-starter-data-redis = { module = "org.springframework.boot:spring-boot-starter-data-redis" }
kotlin-reflect = { module = "org.jetbrains.kotlin:kotlin-reflect" }
jackson3-module-kotlin = { module = "tools.jackson.module:jackson-module-kotlin" }

# Testing (unitTest + functionalTest)
mockk = { module = "io.mockk:mockk", version.ref = "mockk" }
spring-boot-starter-webmvc-test = { module = "org.springframework.boot:spring-boot-starter-webmvc-test" }
spring-boot-starter-restclient-test = { module = "org.springframework.boot:spring-boot-starter-restclient-test" }
spring-boot-testcontainers = { module = "org.springframework.boot:spring-boot-testcontainers" }
testcontainers-junit-jupiter = { module = "org.testcontainers:junit-jupiter" }
testcontainers-postgresql = { module = "org.testcontainers:postgresql" }
wiremock-spring-boot = { module = "org.wiremock.integrations:wiremock-spring-boot", version.ref = "wiremock-spring-boot" }
database-rider-spring = { module = "com.github.database-rider:rider-spring", version.ref = "database-rider" }
database-rider-junit5 = { module = "com.github.database-rider:rider-junit5", version.ref = "database-rider" }

[plugins]
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-spring = { id = "org.jetbrains.kotlin.plugin.spring", version.ref = "kotlin" }
kotlin-jpa = { id = "org.jetbrains.kotlin.plugin.jpa", version.ref = "kotlin" }
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
spring-dependency-management = { id = "io.spring.dependency-management", version.ref = "spring-dependency-management" }
docker-compose = { id = "com.avast.gradle.docker-compose", version.ref = "docker-compose-plugin" }
```

### `build.gradle.kts` (`unitTest`, `functionalTest`, `composeUp` / `composeDown`)
```kotlin
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.kotlin.jpa)
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.spring.dependency.management)
    alias(libs.plugins.docker.compose)
    `jvm-test-suite`
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(25))
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_25)
        freeCompilerArgs.addAll(
            "-Xjsr305=strict",
            "-Xannotation-default-target=param-property",
            "-Xwhen-expressions=indy",
        )
    }
}

// Explicit 3-layer source sets: main, unitTest, functionalTest
sourceSets {
    named("test") {
        kotlin.setSrcDirs(listOf("src/unitTest/kotlin"))
        resources.setSrcDirs(listOf("src/unitTest/resources"))
    }
}

testing {
    suites {
        val test by getting(JvmTestSuite::class) {
            useJUnitJupiter()
            dependencies {
                implementation(libs.mockk)
            }
        }

        val functionalTest by registering(JvmTestSuite::class) {
            useJUnitJupiter()
            testType.set(TestSuiteType.FUNCTIONAL_TEST)
            dependencies {
                implementation(project())
                implementation(libs.spring.boot.starter.webmvc.test)
                implementation(libs.spring.boot.starter.restclient.test)
                implementation(libs.spring.boot.testcontainers)
                implementation(libs.testcontainers.junit.jupiter)
                implementation(libs.testcontainers.postgresql)
                implementation(libs.wiremock.spring.boot)
                implementation(libs.database.rider.spring)
                implementation(libs.database.rider.junit5)
            }
        }
    }
}

tasks.register("unitTest") {
    group = "verification"
    description = "Runs pure unit tests from src/unitTest."
    dependsOn(tasks.named("test"))
}

// Docker Compose lifecycle: ./gradlew composeUp and ./gradlew composeDown
dockerCompose {
    useComposeFiles.set(listOf("compose.yaml"))
    waitForTcpPorts.set(true)
    isRequiredBy(tasks.named("functionalTest"))
}

dependencies {
    implementation(libs.spring.boot.starter.webmvc)
    implementation(libs.spring.boot.starter.data.jpa)
    implementation(libs.spring.boot.starter.restclient)
    implementation(libs.spring.boot.starter.validation)
    implementation(libs.spring.boot.starter.data.redis)
    implementation(libs.kotlin.reflect)
    implementation(libs.jackson3.module.kotlin)
}
```

### `compose.yaml` (Used by `./gradlew composeUp` and `./gradlew composeDown`)
```yaml
services:
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: order_db
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    ports:
      - "5432:5432"
  redis:
    image: redis:7.4-alpine
    ports:
      - "6379:6379"
```

### Multi-Module Topology (`build-logic/` Composite Build)
```text
my-platform/
├── gradle/
│   └── libs.versions.toml
├── compose.yaml
├── build-logic/
│   ├── settings.gradle.kts
│   ├── build.gradle.kts
│   └── src/main/kotlin/
│       ├── buildlogic.kotlin-common.gradle.kts
│       ├── buildlogic.spring-library.gradle.kts
│       └── buildlogic.spring-app.gradle.kts
├── modules/
│   ├── order/
│   │   ├── src/main/kotlin/com/acme/order/{configuration,controller,application,util}/...
│   │   ├── src/unitTest/kotlin/com/acme/order/...
│   │   └── src/functionalTest/kotlin/com/acme/order/...
│   └── billing/
│       ├── src/main/kotlin/com/acme/billing/{configuration,controller,application,util}/...
│       ├── src/unitTest/kotlin/com/acme/billing/...
│       └── src/functionalTest/kotlin/com/acme/billing/...
└── settings.gradle.kts   # includes `includeBuild("build-logic")`
```

### `application.yml` (Virtual Threads + JPA)
```yaml
spring:
  application:
    name: order-service
  threads:
    virtual:
      enabled: true
  jpa:
    open-in-view: false
    hibernate:
      ddl-auto: validate
```

---

## 2. Package-by-Package Reference Implementations (`src/main`)

### 2.1 `configuration/`
```kotlin
package com.acme.order.configuration

import com.acme.order.application.client.InventoryClient
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.boot.context.properties.EnableConfigurationProperties
import org.springframework.context.annotation.Configuration
import org.springframework.context.annotation.Import
import org.springframework.context.support.BeanRegistrarDsl
import org.springframework.web.client.RestClient
import org.springframework.web.client.support.RestClientAdapter
import org.springframework.web.service.invoker.HttpServiceProxyFactory
import java.time.Duration

@ConfigurationProperties(prefix = "app.inventory")
data class InventoryClientProperties(
    val baseUrl: String,
    val timeout: Duration = Duration.ofSeconds(3),
)

class OrderBeanRegistrar : BeanRegistrarDsl({
    registerBean<InventoryClient> {
        val props = bean<InventoryClientProperties>()
        val restClient = bean<RestClient.Builder>()
            .baseUrl(props.baseUrl)
            .build()
        val adapter = RestClientAdapter.create(restClient)
        HttpServiceProxyFactory.builderFor(adapter).build().createClient(InventoryClient::class.java)
    }
})

@Configuration
@EnableConfigurationProperties(InventoryClientProperties::class)
@Import(OrderBeanRegistrar::class)
class OrderConfiguration
```

### 2.2 `controller/`, `controller/request/`, `controller/response/`

#### `controller/request/CreateOrderRequest.kt`
```kotlin
package com.acme.order.controller.request

import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank

data class CreateOrderRequest(
    @NotBlank val sku: String,
    @Min(1) val quantity: Int,
)
```

#### `controller/response/OrderResponse.kt`
```kotlin
package com.acme.order.controller.response

import java.time.Instant
import java.util.UUID

data class OrderResponse(
    val id: UUID,
    val sku: String,
    val quantity: Int,
    val status: String,
    val createdAt: Instant,
)
```

#### `controller/OrderController.kt`
```kotlin
package com.acme.order.controller

import com.acme.order.application.service.OrderService
import com.acme.order.controller.request.CreateOrderRequest
import com.acme.order.controller.response.OrderResponse
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.util.UUID

@RestController
@RequestMapping("/api/orders")
class OrderController(
    private val orderService: OrderService,
) {
    @PostMapping(version = "1.0")
    @ResponseStatus(HttpStatus.CREATED)
    fun createOrder(@Valid @RequestBody request: CreateOrderRequest): OrderResponse {
        val result = orderService.placeOrder(sku = request.sku, quantity = request.quantity)
        return OrderResponse(
            id = result.id,
            sku = result.sku,
            quantity = result.quantity,
            status = result.status,
            createdAt = result.createdAt,
        )
    }

    @GetMapping("/{id}", version = "1.0")
    fun getOrder(@PathVariable id: UUID): OrderResponse {
        val result = orderService.getOrder(id)
        return OrderResponse(
            id = result.id,
            sku = result.sku,
            quantity = result.quantity,
            status = result.status,
            createdAt = result.createdAt,
        )
    }
}
```

### 2.3 `application/service/` (Orchestration — No `@Transactional`)
```kotlin
package com.acme.order.application.service

import com.acme.order.application.client.InventoryClient
import com.acme.order.application.entity.OrderEntity
import com.acme.order.application.repository.kv.OrderCacheKvRepository
import com.acme.order.application.transaction.OrderTransactionService
import com.acme.order.util.DateTimeUtil
import org.springframework.http.HttpStatus
import org.springframework.http.ProblemDetail
import org.springframework.stereotype.Service
import org.springframework.web.ErrorResponseException
import java.util.UUID

@Service
class OrderService(
    private val inventoryClient: InventoryClient,
    private val orderCacheKvRepository: OrderCacheKvRepository,
    private val orderTransactionService: OrderTransactionService,
) {
    fun placeOrder(sku: String, quantity: Int): OrderEntity {
        val stock = inventoryClient.checkStock(sku)
        if (stock == null || stock.available < quantity) {
            throw ErrorResponseException(
                HttpStatus.CONFLICT,
                ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, "Insufficient stock for SKU $sku"),
                null,
            )
        }

        val saved = orderTransactionService.createOrderRecord(
            sku = sku,
            quantity = quantity,
            now = DateTimeUtil.nowUtc(),
        )

        orderCacheKvRepository.putStatus(saved.id, saved.status)
        return saved
    }

    fun getOrder(id: UUID): OrderEntity =
        orderTransactionService.findRequiredById(id)
}
```

### 2.4 `application/transaction/` (Atomic DB Boundary)
```kotlin
package com.acme.order.application.transaction

import com.acme.order.application.entity.OrderEntity
import com.acme.order.application.repository.entity.OrderEntityRepository
import org.springframework.http.HttpStatus
import org.springframework.http.ProblemDetail
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.ErrorResponseException
import java.time.Instant
import java.util.UUID

@Service
class OrderTransactionService(
    private val orderEntityRepository: OrderEntityRepository,
) {
    @Transactional
    fun createOrderRecord(sku: String, quantity: Int, now: Instant): OrderEntity {
        val entity = OrderEntity(
            id = UUID.randomUUID(),
            sku = sku,
            quantity = quantity,
            status = "CREATED",
            createdAt = now,
        )
        return orderEntityRepository.save(entity)
    }

    @Transactional(readOnly = true)
    fun findRequiredById(id: UUID): OrderEntity =
        orderEntityRepository.findById(id).orElseThrow {
            ErrorResponseException(
                HttpStatus.NOT_FOUND,
                ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, "Order $id not found"),
                null,
            )
        }
}
```

### 2.5 `application/entity/` (Hibernate 7-Safe Entity Class)
```kotlin
package com.acme.order.application.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "orders")
class OrderEntity(
    @Id
    @Column(name = "id", nullable = false, updatable = false)
    val id: UUID,

    @Column(name = "sku", nullable = false)
    val sku: String,

    @Column(name = "quantity", nullable = false)
    var quantity: Int,

    @Column(name = "status", nullable = false)
    var status: String,

    @Column(name = "created_at", nullable = false, updatable = false)
    val createdAt: Instant,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is OrderEntity) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}
```

### 2.6 `application/client/` (Declarative `@HttpExchange` + Resilience)
```kotlin
package com.acme.order.application.client

import org.springframework.resilience.annotation.ConcurrencyLimit
import org.springframework.resilience.annotation.Retryable
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.service.annotation.GetExchange
import org.springframework.web.service.annotation.HttpExchange

@HttpExchange("/internal/inventory")
interface InventoryClient {

    @GetExchange("/{sku}")
    @Retryable(maxAttempts = 3)
    @ConcurrencyLimit(50)
    fun checkStock(@PathVariable sku: String): StockView?
}

data class StockView(
    val sku: String,
    val available: Int,
)
```

### 2.7 `application/repository/kv/` & `application/repository/entity/`

#### `application/repository/kv/OrderCacheKvRepository.kt`
```kotlin
package com.acme.order.application.repository.kv

import org.springframework.data.redis.core.StringRedisTemplate
import org.springframework.stereotype.Repository
import java.time.Duration
import java.util.UUID

@Repository
class OrderCacheKvRepository(
    private val redisTemplate: StringRedisTemplate,
) {
    fun putStatus(orderId: UUID, status: String) {
        redisTemplate.opsForValue().set(key(orderId), status, TTL)
    }

    fun getStatus(orderId: UUID): String? =
        redisTemplate.opsForValue().get(key(orderId))

    private fun key(orderId: UUID): String = "order:status:$orderId"

    companion object {
        private val TTL: Duration = Duration.ofMinutes(15)
    }
}
```

#### `application/repository/entity/OrderEntityRepository.kt`
```kotlin
package com.acme.order.application.repository.entity

import com.acme.order.application.entity.OrderEntity
import org.springframework.data.jpa.repository.JpaRepository
import java.util.UUID

interface OrderEntityRepository : JpaRepository<OrderEntity, UUID> {
    fun findAllBySku(sku: String): List<OrderEntity>
}
```

### 2.8 `util/` (Stateless Pure Utilities)
```kotlin
package com.acme.order.util

import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

object DateTimeUtil {
    fun nowUtc(clock: Clock = Clock.systemUTC()): Instant =
        Instant.now(clock)

    fun toUtcDate(instant: Instant): LocalDate =
        instant.atZone(ZoneOffset.UTC).toLocalDate()
}
```

---

## 3. Two-Layer Testing Reference Implementations (`unitTest` & `functionalTest`)

### 3.1 `src/unitTest/` (Pure Unit Test — All Dependencies Mocked)
```kotlin
package com.acme.order.application.service

import com.acme.order.application.client.InventoryClient
import com.acme.order.application.client.StockView
import com.acme.order.application.entity.OrderEntity
import com.acme.order.application.repository.kv.OrderCacheKvRepository
import com.acme.order.application.transaction.OrderTransactionService
import io.mockk.every
import io.mockk.justRun
import io.mockk.mockk
import io.mockk.verify
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.UUID

class OrderServiceUnitTest {
    private val inventoryClient: InventoryClient = mockk()
    private val orderCacheKvRepository: OrderCacheKvRepository = mockk()
    private val orderTransactionService: OrderTransactionService = mockk()

    private val orderService = OrderService(
        inventoryClient = inventoryClient,
        orderCacheKvRepository = orderCacheKvRepository,
        orderTransactionService = orderTransactionService,
    )

    @Test
    fun `placeOrder verifies stock, persists via transaction service, and caches status`() {
        val orderId = UUID.randomUUID()
        val expectedEntity = OrderEntity(
            id = orderId,
            sku = "SKU-100",
            quantity = 2,
            status = "CREATED",
            createdAt = Instant.parse("2026-01-01T00:00:00Z"),
        )

        every { inventoryClient.checkStock("SKU-100") } returns StockView(sku = "SKU-100", available = 10)
        every { orderTransactionService.createOrderRecord("SKU-100", 2, any()) } returns expectedEntity
        justRun { orderCacheKvRepository.putStatus(orderId, "CREATED") }

        val actual = orderService.placeOrder(sku = "SKU-100", quantity = 2)

        assertEquals(orderId, actual.id)
        verify(exactly = 1) { inventoryClient.checkStock("SKU-100") }
        verify(exactly = 1) { orderTransactionService.createOrderRecord("SKU-100", 2, any()) }
        verify(exactly = 1) { orderCacheKvRepository.putStatus(orderId, "CREATED") }
    }
}
```

### 3.2 `src/functionalTest/` (E2E Internal API + Testcontainers + WireMock + Database Rider)

#### `src/functionalTest/kotlin/com/acme/order/controller/OrderFunctionalTest.kt`
```kotlin
package com.acme.order.controller

import com.acme.order.controller.request.CreateOrderRequest
import com.acme.order.controller.response.OrderResponse
import com.github.database.rider.core.api.dataset.DataSet
import com.github.database.rider.core.api.dataset.ExpectedDataSet
import com.github.database.rider.spring.api.DBRider
import com.github.tomakehurst.wiremock.client.WireMock.aResponse
import com.github.tomakehurst.wiremock.client.WireMock.get
import com.github.tomakehurst.wiremock.client.WireMock.stubFor
import com.github.tomakehurst.wiremock.client.WireMock.urlEqualTo
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.client.TestRestTemplate
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.springframework.http.HttpStatus
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import org.wiremock.spring.ConfigureWireMock
import org.wiremock.spring.EnableWireMock

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@DBRider
@EnableWireMock(
    ConfigureWireMock(
        name = "inventory-service",
        baseUrlProperties = ["app.inventory.base-url"],
    ),
)
class OrderFunctionalTest(
    @Autowired private val restTemplate: TestRestTemplate,
) {
    companion object {
        @Container
        @ServiceConnection
        @JvmStatic
        val postgres: PostgreSQLContainer<*> = PostgreSQLContainer("postgres:17-alpine")
    }

    @Test
    @DataSet(value = ["datasets/orders-empty.yml"], cleanBefore = true)
    @ExpectedDataSet(value = ["datasets/orders-created.yml"], ignoreCols = ["id", "created_at"])
    fun `POST orders creates order in database when external inventory has stock`() {
        stubFor(
            get(urlEqualTo("/internal/inventory/SKU-100"))
                .willReturn(
                    aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withBody("""{"sku":"SKU-100","available":5}"""),
                ),
        )

        val response = restTemplate.postForEntity(
            "/api/orders",
            CreateOrderRequest(sku = "SKU-100", quantity = 2),
            OrderResponse::class.java,
        )

        assertEquals(HttpStatus.CREATED, response.statusCode)
        assertEquals("SKU-100", response.body?.sku)
        assertEquals("CREATED", response.body?.status)
    }
}
```

#### `src/functionalTest/resources/datasets/orders-empty.yml`
```yaml
orders: []
```

#### `src/functionalTest/resources/datasets/orders-created.yml`
```yaml
orders:
  - sku: "SKU-100"
    quantity: 2
    status: "CREATED"
```
