#!/usr/bin/env python3
"""LLM behavioral eval for the implement-spring-kotlin-core skill (deepeval).

This is the optional, non-blocking companion to the deterministic gate in
evals/run_eval.sh. The unit under test is the skill text itself: the model
generates project layouts or Kotlin source/test files with SKILL.md in context,
then the output is graded in two layers:

  1. Deterministic — the bundled checkers (scripts/check-layout.sh and
     scripts/check-source.sh) validate every generated layout or Kotlin
     source/test file. What has ground truth is never left to a judge.
  2. GEval — judges what static checkers cannot express: architectural
     responsibility alignment, transactional orchestration semantics,
     two-layer testing fidelity (unitTest vs functionalTest), and idiomatic
     Spring Boot 4 + Kotlin 2 + Java 25 usage.

Run via evals/run_eval_llm.sh, which requires OPENAI_BASE_URL,
OPENAI_API_KEY, and OPENAI_DEFAULT_MODEL in the environment
(OpenAI-compatible endpoint). The key value is never printed, logged, or
persisted — only its presence is checked. Generation and judging share the
same endpoint and model; the model name is never hardcoded — it always
comes from OPENAI_DEFAULT_MODEL.
"""

import os
import re
import subprocess
from pathlib import Path

os.environ.setdefault("DEEPEVAL_PER_ATTEMPT_TIMEOUT_SECONDS_OVERRIDE", "240")

import pytest
from deepeval import assert_test
from deepeval.metrics import GEval
from deepeval.models import LocalModel
from deepeval.test_case import LLMTestCase

try:  # deepeval >= 2.x
    from deepeval.test_case import SingleTurnParams as Params
except ImportError:  # older deepeval
    from deepeval.test_case import LLMTestCaseParams as Params

LLM_DIR = Path(__file__).resolve().parent
SKILL_DIR = LLM_DIR.parent.parent
SKILL_MD = (SKILL_DIR / "SKILL.md").read_text(encoding="utf-8")
LAYOUT_CHECKER = SKILL_DIR / "scripts" / "check-layout.sh"
SOURCE_CHECKER = SKILL_DIR / "scripts" / "check-source.sh"

pytestmark = pytest.mark.skipif(
    not os.environ.get("OPENAI_API_KEY")
    or not os.environ.get("OPENAI_BASE_URL")
    or not os.environ.get("OPENAI_DEFAULT_MODEL"),
    reason="OPENAI_API_KEY / OPENAI_BASE_URL / OPENAI_DEFAULT_MODEL not set "
           "(run via evals/run_eval_llm.sh)",
)

# --- scenarios -----------------------------------------------------------
# reference_output is one reasonable answer fed to GEval as 'expected output'
# to anchor semantic judging — never matched literally.

SCENARIOS = [
    {
        "id": "single_module_payment_layout",
        "kind": "layout",
        "scenario": (
            "Propose the relative file path list for a single-module Spring Boot 4 + "
            "Kotlin 2 'payment' service under base package 'com.acme.payment'. "
            "Include gradle/libs.versions.toml, build.gradle.kts, compose.yaml, "
            "at least one representative .kt file inside every required standard "
            "package under src/main/kotlin/com/acme/payment/, a unit test file under "
            "src/unitTest/kotlin/com/acme/payment/, and a functional test file plus "
            "Database Rider dataset under src/functionalTest/."
        ),
        "reference_output": (
            "gradle/libs.versions.toml\n"
            "build.gradle.kts\n"
            "compose.yaml\n"
            "src/main/kotlin/com/acme/payment/PaymentApplication.kt\n"
            "src/main/kotlin/com/acme/payment/configuration/PaymentConfiguration.kt\n"
            "src/main/kotlin/com/acme/payment/controller/PaymentController.kt\n"
            "src/main/kotlin/com/acme/payment/controller/request/CreatePaymentRequest.kt\n"
            "src/main/kotlin/com/acme/payment/controller/response/PaymentResponse.kt\n"
            "src/main/kotlin/com/acme/payment/application/service/PaymentService.kt\n"
            "src/main/kotlin/com/acme/payment/application/transaction/PaymentTransactionService.kt\n"
            "src/main/kotlin/com/acme/payment/application/entity/PaymentEntity.kt\n"
            "src/main/kotlin/com/acme/payment/application/client/FraudCheckClient.kt\n"
            "src/main/kotlin/com/acme/payment/application/repository/kv/PaymentCacheKvRepository.kt\n"
            "src/main/kotlin/com/acme/payment/application/repository/entity/PaymentEntityRepository.kt\n"
            "src/main/kotlin/com/acme/payment/util/DateTimeUtil.kt\n"
            "src/unitTest/kotlin/com/acme/payment/application/service/PaymentServiceUnitTest.kt\n"
            "src/functionalTest/kotlin/com/acme/payment/controller/PaymentFunctionalTest.kt\n"
            "src/functionalTest/resources/datasets/payments.yml"
        ),
    },
    {
        "id": "multi_module_commerce_layout",
        "kind": "layout",
        "scenario": (
            "Propose the relative file path list for a multi-module Gradle Spring Boot 4 + "
            "Kotlin 2 project containing a shared composite build for convention plugins, "
            "a version catalog, compose.yaml, and a 'modules/catalog' module with base "
            "package 'com.acme.catalog' containing all 3 source sets (src/main with all 10 "
            "standard packages, src/unitTest, and src/functionalTest)."
        ),
        "reference_output": (
            "gradle/libs.versions.toml\n"
            "settings.gradle.kts\n"
            "compose.yaml\n"
            "build-logic/build.gradle.kts\n"
            "modules/catalog/build.gradle.kts\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/configuration/CatalogConfiguration.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/controller/CatalogController.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/controller/request/CreateItemRequest.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/controller/response/ItemResponse.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/application/service/CatalogService.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/application/transaction/CatalogTransactionService.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/application/entity/ItemEntity.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/application/client/SupplierClient.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/application/repository/kv/ItemCacheKvRepository.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/application/repository/entity/ItemEntityRepository.kt\n"
            "modules/catalog/src/main/kotlin/com/acme/catalog/util/SlugUtil.kt\n"
            "modules/catalog/src/unitTest/kotlin/com/acme/catalog/application/service/CatalogServiceUnitTest.kt\n"
            "modules/catalog/src/functionalTest/kotlin/com/acme/catalog/controller/CatalogFunctionalTest.kt"
        ),
    },
    {
        "id": "service_and_transaction_separation",
        "kind": "source",
        "scenario": (
            "Write a single Kotlin file for 'PaymentService' in package "
            "'com.acme.payment.application.service'. It must orchestrate charging a "
            "payment by: (1) calling 'FraudCheckClient.verify(accountId, amount)' "
            "(from 'com.acme.payment.application.client.FraudCheckClient'), "
            "(2) persisting the payment record via 'PaymentTransactionService.recordPayment(accountId, amount)' "
            "(from 'com.acme.payment.application.transaction.PaymentTransactionService') "
            "which returns 'PaymentEntity' ('com.acme.payment.application.entity.PaymentEntity'), and "
            "(3) caching the payment status in 'PaymentCacheKvRepository.putStatus(paymentId, status)' "
            "(from 'com.acme.payment.application.repository.kv.PaymentCacheKvRepository'). "
            "Follow all Virtual Threads and transactional boundary rules."
        ),
        "reference_output": (
            "package com.acme.payment.application.service\n\n"
            "import com.acme.payment.application.client.FraudCheckClient\n"
            "import com.acme.payment.application.entity.PaymentEntity\n"
            "import com.acme.payment.application.repository.kv.PaymentCacheKvRepository\n"
            "import com.acme.payment.application.transaction.PaymentTransactionService\n"
            "import org.springframework.stereotype.Service\n"
            "import java.util.UUID\n\n"
            "@Service\n"
            "class PaymentService(\n"
            "    private val fraudCheckClient: FraudCheckClient,\n"
            "    private val paymentTransactionService: PaymentTransactionService,\n"
            "    private val paymentCacheKvRepository: PaymentCacheKvRepository,\n"
            ") {\n"
            "    fun charge(accountId: UUID, amount: Long): PaymentEntity {\n"
            "        fraudCheckClient.verify(accountId, amount)\n"
            "        val saved = paymentTransactionService.recordPayment(accountId, amount)\n"
            "        paymentCacheKvRepository.putStatus(saved.id, saved.status)\n"
            "        return saved\n"
            "    }\n"
            "}"
        ),
    },
    {
        "id": "refactor_legacy_jpa_entity",
        "kind": "source",
        "scenario": (
            "Refactor the following broken legacy Kotlin JPA entity so it strictly "
            "complies with the skill rules for package 'com.acme.payment.application.entity':\n\n"
            "package com.acme.payment.application.entity\n"
            "import javax.persistence.Entity\n"
            "import javax.persistence.Id\n"
            "import javax.persistence.Table\n"
            "import java.util.Date\n"
            "import java.util.UUID\n"
            "@Entity\n"
            "@Table(name = \"payments\")\n"
            "data class PaymentEntity(\n"
            "    @Id val id: UUID,\n"
            "    val amount: Long,\n"
            "    val status: String,\n"
            "    val createdAt: Date,\n"
            ")"
        ),
        "reference_output": (
            "package com.acme.payment.application.entity\n\n"
            "import jakarta.persistence.Column\n"
            "import jakarta.persistence.Entity\n"
            "import jakarta.persistence.Id\n"
            "import jakarta.persistence.Table\n"
            "import java.time.Instant\n"
            "import java.util.UUID\n\n"
            "@Entity\n"
            "@Table(name = \"payments\")\n"
            "class PaymentEntity(\n"
            "    @Id\n"
            "    @Column(name = \"id\", nullable = false, updatable = false)\n"
            "    val id: UUID,\n"
            "    @Column(name = \"amount\", nullable = false)\n"
            "    val amount: Long,\n"
            "    @Column(name = \"status\", nullable = false)\n"
            "    var status: String,\n"
            "    @Column(name = \"created_at\", nullable = false, updatable = false)\n"
            "    val createdAt: Instant,\n"
            ") {\n"
            "    override fun equals(other: Any?): Boolean {\n"
            "        if (this === other) return true\n"
            "        if (other !is PaymentEntity) return false\n"
            "        return id == other.id\n"
            "    }\n\n"
            "    override fun hashCode(): Int = id.hashCode()\n"
            "}"
        ),
    },
    {
        "id": "functional_test_e2e_wiremock_dbrider",
        "kind": "source",
        "scenario": (
            "Write a minimal Kotlin functionalTest skeleton class 'PaymentFunctionalTest' in "
            "package 'com.acme.payment.controller' with: "
            "(1) '@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)', "
            "'@Testcontainers', '@DBRider', and '@EnableWireMock' on the class, "
            "(2) a companion object defining '@Container @ServiceConnection @JvmStatic val postgres = PostgreSQLContainer(\"postgres:17-alpine\")', and "
            "(3) one minimal '@Test' method annotated with '@DataSet(\"datasets/empty.yml\")' and "
            "'@ExpectedDataSet(\"datasets/expected.yml\")' that calls WireMock 'stubFor(...)'."
        ),
        "reference_output": (
            "package com.acme.payment.controller\n\n"
            "import com.github.database.rider.core.api.dataset.DataSet\n"
            "import com.github.database.rider.core.api.dataset.ExpectedDataSet\n"
            "import com.github.database.rider.spring.api.DBRider\n"
            "import com.github.tomakehurst.wiremock.client.WireMock.aResponse\n"
            "import com.github.tomakehurst.wiremock.client.WireMock.post\n"
            "import com.github.tomakehurst.wiremock.client.WireMock.stubFor\n"
            "import com.github.tomakehurst.wiremock.client.WireMock.urlEqualTo\n"
            "import org.junit.jupiter.api.Test\n"
            "import org.springframework.beans.factory.annotation.Autowired\n"
            "import org.springframework.boot.test.context.SpringBootTest\n"
            "import org.springframework.boot.test.web.client.TestRestTemplate\n"
            "import org.springframework.boot.testcontainers.service.connection.ServiceConnection\n"
            "import org.testcontainers.containers.PostgreSQLContainer\n"
            "import org.testcontainers.junit.jupiter.Container\n"
            "import org.testcontainers.junit.jupiter.Testcontainers\n"
            "import org.wiremock.spring.EnableWireMock\n\n"
            "@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)\n"
            "@Testcontainers\n"
            "@DBRider\n"
            "@EnableWireMock\n"
            "class PaymentFunctionalTest(\n"
            "    @Autowired private val restTemplate: TestRestTemplate,\n"
            ") {\n"
            "    companion object {\n"
            "        @Container\n"
            "        @ServiceConnection\n"
            "        @JvmStatic\n"
            "        val postgres: PostgreSQLContainer<*> = PostgreSQLContainer(\"postgres:17-alpine\")\n"
            "    }\n\n"
            "    @Test\n"
            "    @DataSet(\"datasets/payments-empty.yml\")\n"
            "    @ExpectedDataSet(\"datasets/payments-expected.yml\")\n"
            "    fun `should create payment e2e`() {\n"
            "        stubFor(post(urlEqualTo(\"/fraud/verify\")).willReturn(aResponse().withStatus(200)))\n"
            "    }\n"
            "}"
        ),
    },
]

# --- shared model & metrics (lazy, so collection works without credentials) ---

_MODEL = None
_METRICS = None


def model():
    global _MODEL
    if _MODEL is None:
        _MODEL = LocalModel(
            model=os.environ["OPENAI_DEFAULT_MODEL"],
            base_url=os.environ["OPENAI_BASE_URL"],
            api_key=os.environ["OPENAI_API_KEY"],
            temperature=0,
            format="text",
        )
    return _MODEL


def metrics():
    global _METRICS
    if _METRICS is None:
        judge = model()
        _METRICS = [
            GEval(
                name="Architectural boundary fidelity",
                evaluation_steps=[
                    "Read the scenario and the skill rules in 'input'; treat 'expected output' as a semantic reference, not a literal string match.",
                    "For layout scenarios, verify that the paths include all three source sets (src/main, src/unitTest, src/functionalTest), the 10 required packages under src/main, and multi-module rules (build-logic + libs.versions.toml, no buildSrc, no src/test).",
                    "For source and test scenarios, verify that layer responsibilities and test boundaries are respected (application.service has no @Transactional and delegates DB writes to application.transaction; functionalTest uses @SpringBootTest RANDOM_PORT + Testcontainers + WireMock + Database Rider @DBRider/@DataSet/@ExpectedDataSet without @MockBean).",
                    "Award a full score (10/10) if all architectural boundaries and responsibilities in the scenario are satisfied.",
                ],
                evaluation_params=[
                    Params.INPUT,
                    Params.ACTUAL_OUTPUT,
                    Params.EXPECTED_OUTPUT,
                ],
                threshold=0.7,
                model=judge,
            ),
            GEval(
                name="Spring Boot 4 and Kotlin 2 idiom quality",
                evaluation_steps=[
                    "Compare 'actual output' against the skill rules in 'input' and semantic reference in 'expected output'.",
                    "For source and test scenarios, verify modern idioms: constructor injection, jakarta.* namespaces, java.time.* types (no java.util.Date), regular Kotlin class for @Entity with ID-based equality (no data class on @Entity), @ServiceConnection for Testcontainers, and no Virtual Thread pinning constructs.",
                    "For layout scenarios, verify clean naming and placement of files inside their respective packages and source sets.",
                ],
                evaluation_params=[
                    Params.INPUT,
                    Params.ACTUAL_OUTPUT,
                    Params.EXPECTED_OUTPUT,
                ],
                threshold=0.7,
                model=judge,
            ),
        ]
    return _METRICS


# --- helpers ---------------------------------------------------------------


def generate_layout(scenario_text):
    prompt = (
        "You are an agent that has loaded the following skill. Follow it strictly.\n\n"
        f"<skill>\n{SKILL_MD}\n</skill>\n\n"
        f"Task: {scenario_text}\n\n"
        "Respond with ONLY the relative file paths, one path per line — "
        "no bullets, no numbering, no tree characters, no code fences, no explanation."
    )
    out = model().generate(prompt)
    if isinstance(out, tuple):
        out = out[0]
    raw = str(out).strip()

    paths = []
    for line in raw.splitlines():
        line = line.strip().strip("`")
        line = re.sub(r"^[-*\d.)\s]+", "", line).strip()
        if not line or line.startswith("#"):
            continue
        paths.append(line)
    assert paths, f"model produced no file paths\nraw output:\n{raw}"
    return prompt, paths


def generate_source(scenario_text):
    prompt = (
        "You are an agent that has loaded the following skill. Follow it strictly.\n\n"
        f"<skill>\n{SKILL_MD}\n</skill>\n\n"
        f"Task: {scenario_text}\n\n"
        "Respond with ONLY concise, valid Kotlin source code for the requested file — "
        "no comments, no KDoc, no markdown prose, and no explanation."
    )
    out = model().generate(prompt)
    if isinstance(out, tuple):
        out = out[0]
    raw = str(out).strip()

    fence_match = re.search(r"```(?:kotlin|kt)?\s*\n(.*?)```", raw, re.DOTALL)
    code = fence_match.group(1).strip() if fence_match else raw.strip("`").strip()
    assert "package " in code, f"model output does not contain a Kotlin package declaration:\n{raw}"
    return prompt, code


def run_layout_checker(paths):
    proc = subprocess.run(
        ["bash", str(LAYOUT_CHECKER), "--paths", "\n".join(paths)],
        cwd=SKILL_DIR,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, (
        f"check-layout.sh rejected generated layout (exit {proc.returncode})\n"
        f"paths:\n" + "\n".join(paths) + f"\nstderr: {proc.stderr.strip()}"
    )


def run_source_checker(code):
    proc = subprocess.run(
        ["bash", str(SOURCE_CHECKER), "--code", code],
        cwd=SKILL_DIR,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, (
        f"check-source.sh rejected generated Kotlin code (exit {proc.returncode})\n"
        f"code:\n{code}\nstderr: {proc.stderr.strip()}"
    )


# --- tests -----------------------------------------------------------------


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s["id"])
def test_skill_scenario(scenario):
    if scenario["kind"] == "layout":
        prompt, paths = generate_layout(scenario["scenario"])
        run_layout_checker(paths)
        actual_output = "\n".join(paths)
    else:
        prompt, code = generate_source(scenario["scenario"])
        run_source_checker(code)
        actual_output = code

    test_case = LLMTestCase(
        input=prompt,
        actual_output=actual_output,
        expected_output=scenario["reference_output"],
    )
    assert_test(test_case, metrics())
