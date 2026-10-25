"""LLM behavioral evals for the implement-go-api skill (optional suite).

The model under test generates behavior with SKILL.md in context. Bundled
deterministic checkers grade everything they can (layout rules, exit codes);
GEval judges only what checkers cannot express (boundary decisions, rationale,
semantic layout quality). Reference expectations anchor the judge and are
compared semantically, never literally.

Endpoint, credentials, and model come exclusively from these environment
variables — never hardcoded, never silently defaulted, never echoed:
  OPENAI_BASE_URL, OPENAI_API_KEY, OPENAI_DEFAULT_MODEL
Generation and judging share the same endpoint and model.
"""

import json
import os
import ssl
import subprocess
import urllib.request
from pathlib import Path

import pytest
from deepeval.metrics import GEval
from deepeval.test_case import LLMTestCase, LLMTestCaseParams

try:
    import certifi  # provided transitively by deepeval's dependencies
    _SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except ImportError:  # pragma: no cover — fall back to system trust store
    _SSL_CONTEXT = ssl.create_default_context()

SKILL_DIR = Path(__file__).resolve().parents[2]
SKILL_MD = (SKILL_DIR / "SKILL.md").read_text(encoding="utf-8")
THRESHOLD = 0.7

ANTIPATTERN_SERVICE = """package user

import (
\t"github.com/gin-gonic/gin"
)

func ListActive(c *gin.Context) []string {
\treturn []string{}
}
"""

ANTIPATTERN_HANDLER = """package user

import (
\t"github.com/gin-gonic/gin"
)

type CreateUserRequest struct {
\tUsername string `json:"username" binding:"required"`
}

func create(c *gin.Context) {
\tvar req CreateUserRequest
\tif err := c.BindJSON(&req); err != nil {
\t\treturn
\t}
\tc.JSON(201, gin.H{"ok": true})
}
"""


def _env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(
            f"Missing required environment variable {name!r} — LLM evals take "
            "endpoint, credentials and model exclusively from OPENAI_BASE_URL, "
            "OPENAI_API_KEY and OPENAI_DEFAULT_MODEL"
        )
    return value


def generate(task: str) -> str:
    """Call the OpenAI-compatible endpoint with SKILL.md in context."""
    payload = {
        "model": _env("OPENAI_DEFAULT_MODEL"),
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are a senior Go engineer implementing a Gin API. "
                    "Follow the skill guidance below exactly.\n\n"
                    "<skill>\n" + SKILL_MD + "\n</skill>"
                ),
            },
            {"role": "user", "content": task},
        ],
        "temperature": 0,
    }
    request = urllib.request.Request(
        _env("OPENAI_BASE_URL").rstrip("/") + "/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + _env("OPENAI_API_KEY"),
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=180, context=_SSL_CONTEXT) as response:
        body = json.load(response)
    return body["choices"][0]["message"]["content"]


def extract_json(text: str) -> dict:
    """Extract the outermost JSON object from a model response."""
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        raise AssertionError(f"No JSON object in model response:\n{text[:500]}")
    parsed = json.loads(text[start : end + 1])
    if not isinstance(parsed, dict):
        raise AssertionError(f"Expected a JSON object, got: {type(parsed).__name__}")
    return parsed


def run_checker(script: str, target: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(SKILL_DIR / "scripts" / script), str(target)],
        capture_output=True,
        text=True,
    )


def judge(criteria: str, input_text: str, actual_output: str) -> GEval:
    """GEval judges only what the deterministic checkers cannot express."""
    metric = GEval(
        name="skill-guidance-adherence",
        criteria=criteria,
        evaluation_params=[LLMTestCaseParams.INPUT, LLMTestCaseParams.ACTUAL_OUTPUT],
        model=_env("OPENAI_DEFAULT_MODEL"),
        threshold=THRESHOLD,
    )
    metric.measure(LLMTestCase(input=input_text, actual_output=actual_output))
    print(f"\nGEval score: {metric.score}\nReason: {metric.reason}")
    return metric


def test_scaffold_passes_deterministic_gate_and_judges_layout(tmp_path):
    task = (
        "Create a minimal user-domain Gin API project. Respond ONLY with a JSON "
        "object mapping relative file paths to full file contents. Required "
        "files: go.mod (module example.com/api, go 1.26), cmd/api/main.go, "
        "internal/server/router.go, internal/user/handler.go, "
        "internal/user/service.go, internal/user/repository.go, "
        "internal/user/model.go, internal/user/dto.go. Handlers must bind with "
        "ShouldBindJSON and validation tags live on DTOs."
    )
    output = generate(task)
    files = extract_json(output)
    assert len(files) >= 6, f"expected at least 6 files, got {list(files)}"
    for relpath, content in files.items():
        target = tmp_path / relpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    # Deterministic checker: layout rules must pass outright.
    proc = run_checker("check_layout.sh", tmp_path)
    assert proc.returncode == 0, proc.stdout + proc.stderr

    # GEval: semantic layout quality beyond greppable rules.
    metric = judge(
        "Evaluate whether the generated project follows the domain-modular "
        "Go+Gin layout: one package per domain under internal/ with separated "
        "handler/service/repository/model/dto files, per-domain Register*Routes "
        "functions on gin.RouterGroup, dependencies injected through "
        "constructors, and main.go as a pure composition root that only wires "
        "config, dependencies and the router together.",
        task,
        output,
    )
    assert metric.is_successful()


def test_refactor_antipatterns_and_explain(tmp_path):
    task = (
        "These two files violate the skill rules. Rewrite both so they comply, "
        "and state which antipatterns you fixed and why. Respond ONLY with a "
        "JSON object with keys 'files' (mapping user/service.go and "
        "user/handler.go to full contents) and 'explanation'.\n\n"
        "user/service.go:\n" + ANTIPATTERN_SERVICE + "\n\n"
        "user/handler.go:\n" + ANTIPATTERN_HANDLER
    )
    output = generate(task)
    parsed = extract_json(output)
    assert "explanation" in parsed, "model must explain the fixes"
    files = parsed.get("files", {})
    assert set(files) >= {"user/service.go", "user/handler.go"}
    for relpath, content in files.items():
        target = tmp_path / relpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        # Deterministic checker: every rewritten file must comply.
        proc = run_checker("check_snippet.sh", target)
        assert proc.returncode == 0, f"{relpath}:\n{proc.stdout}{proc.stderr}"

    # GEval: quality of the antipattern rationale.
    metric = judge(
        "Evaluate whether the explanation identifies the actual antipatterns "
        "(gin.Context and gin usage inside the service layer instead of the "
        "transport edge, and the auto-aborting c.BindJSON instead of "
        "c.ShouldBindJSON) and justifies the fixes with the underlying reason "
        "for each rule rather than restating the code change.",
        task,
        output,
    )
    assert metric.is_successful()


def test_boundary_decision_dto_vs_model():
    task = (
        "A UserProfile struct is both persisted to Postgres and returned as a "
        "JSON API response, and its Email field must be validated. In this "
        "layout, where does the struct live and where do the validation tags "
        "go? Answer briefly."
    )
    output = generate(task)
    metric = judge(
        "Evaluate whether the answer applies the skill's separation rule: the "
        "persisted domain struct lives in the domain package (e.g. "
        "internal/user/model.go) free of transport concerns, while a separate "
        "transport DTO (e.g. internal/user/dto.go or a handler request struct) "
        "carries the binding/validation tags for the JSON shape. Reject answers "
        "that put binding tags on the domain model or merge the two concerns.",
        task,
        output,
    )
    assert metric.is_successful()


def test_business_logic_stays_out_of_middleware():
    task = (
        "A teammate wants to compute per-user discount percentages inside a Gin "
        "middleware function because 'it already has the context'. Per the "
        "skill, where should this logic live and why? Answer briefly."
    )
    output = generate(task)
    metric = judge(
        "Evaluate whether the answer keeps business logic out of middleware: "
        "middleware is reserved for cross-cutting request-path concerns (auth, "
        "logging, recovery, request-id), the discount computation belongs in "
        "the domain service layer with constructor-injected dependencies so it "
        "is unit-testable, and gin.Context stays at the handler edge.",
        task,
        output,
    )
    assert metric.is_successful()
