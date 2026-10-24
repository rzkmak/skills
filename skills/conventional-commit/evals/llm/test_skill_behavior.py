#!/usr/bin/env python3
"""LLM behavioral eval for the conventional-commit skill (deepeval).

This is the optional, non-blocking companion to the deterministic gate in
evals/run_eval.sh. The unit under test is the skill text itself: the model
drafts commit messages with SKILL.md in context, then the output is graded
in two layers:

  1. Deterministic — the bundled checkers (scripts/check-commit-msg.sh,
     scripts/check-commit-plan.sh) validate every header, and each scenario
     asserts a commit-count range. What has ground truth is never left to
     a judge.
  2. GEval — judges only what the checkers cannot express: whether commits
     are grouped along purpose boundaries and whether types/scopes/breaking
     markers semantically match the described changes.

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
MSG_CHECKER = SKILL_DIR / "scripts" / "check-commit-msg.sh"
PLAN_CHECKER = SKILL_DIR / "scripts" / "check-commit-plan.sh"

HEADER_RE = re.compile(
    r"^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)"
    r"(\([^)]+\))?!?: \S.*$"
)

pytestmark = pytest.mark.skipif(
    not os.environ.get("OPENAI_API_KEY")
    or not os.environ.get("OPENAI_BASE_URL")
    or not os.environ.get("OPENAI_DEFAULT_MODEL"),
    reason="OPENAI_API_KEY / OPENAI_BASE_URL / OPENAI_DEFAULT_MODEL not set "
           "(run via evals/run_eval_llm.sh)",
)

# --- scenarios -----------------------------------------------------------
# expected_commits is the deterministic commit-count range for the scenario.
# reference_plan is one reasonable answer, fed to GEval as 'expected output'
# to anchor judging — it is a semantic reference, never matched literally.

SCENARIOS = [
    {
        "id": "single_cohesive_change",
        "scenario": (
            "The user asks to add a JWT token refresh endpoint to the auth module. "
            "The diff touches src/auth/refresh.py (new endpoint) and "
            "tests/auth/test_refresh.py (tests for it). All changes serve one purpose."
        ),
        "expected_commits": (1, 1),
        "reference_plan": "feat(auth): add jwt token refresh endpoint",
    },
    {
        "id": "mixed_unrelated_concerns",
        "scenario": (
            "The diff contains three unrelated changes: a new retry-with-backoff "
            "feature in src/payments/retry.py; a typo fix in README.md; and a "
            "version bump in pyproject.toml. Each serves a different purpose."
        ),
        "expected_commits": (2, 3),
        "reference_plan": (
            "feat(payments): add retry with backoff\n"
            "docs: fix readme typo\n"
            "chore: bump version"
        ),
    },
    {
        "id": "single_purpose_rename",
        "scenario": (
            "A mechanical rename of the function fetch_data to fetch_payload "
            "across 14 files, including all call sites and their tests. The "
            "change serves exactly one purpose."
        ),
        "expected_commits": (1, 2),
        "reference_plan": "refactor: rename fetch_data to fetch_payload",
    },
    {
        "id": "formatting_traps",
        "scenario": (
            "The user asks to 'Update the docs to explain the new Rate Limiter.' "
            "The diff only edits docs/rate-limiter.md. Note how the request is "
            "phrased with a capital letter and a trailing period."
        ),
        "expected_commits": (1, 1),
        "reference_plan": "docs: explain the new rate limiter",
    },
    {
        "id": "breaking_api_change",
        "scenario": (
            "The diff changes the public API: parse_config(path) now requires a "
            "second, mandatory argument, and every caller is updated. This is a "
            "breaking change for API consumers."
        ),
        "expected_commits": (1, 1),
        "reference_plan": "feat(config)!: require second argument for parse_config",
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
                name="Splitting quality",
                evaluation_steps=[
                    "Read the scenario and the skill rules in 'input'; treat 'expected output' as one reasonable reference plan, not a literal answer.",
                    "Penalize grouping unrelated purposes (as described in 'input') into a single commit.",
                    "Penalize splitting changes that serve a single purpose into multiple commits.",
                    "Penalize more commits than there are distinct purposes in the scenario (over-splitting).",
                    "Score 1 only if each commit covers exactly one purpose and the count is the fewest that achieves it.",
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
                name="Type semantics",
                evaluation_steps=[
                    "For each commit header in 'actual output', check that its type (feat, fix, docs, chore, refactor, ...) semantically matches the change it covers per 'input'.",
                    "Check that the scope, if present, names the subsystem the change touches.",
                    "Penalize a breaking API change that is not marked with '!' after the type/scope (or a BREAKING CHANGE footer).",
                    "Ignore header formatting details (case, punctuation) — other checks cover those.",
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


def draft_commits(scenario_text):
    prompt = (
        "You are an agent that has loaded the following skill. Follow it exactly.\n\n"
        f"<skill>\n{SKILL_MD}\n</skill>\n\n"
        f"Task: {scenario_text}\n\n"
        "Respond with ONLY the commit message header lines, one per line — "
        "no bullets, no numbering, no code fences, no explanation."
    )
    out = model().generate(prompt)
    if isinstance(out, tuple):  # some deepeval versions return (output, cost)
        out = out[0]
    raw = str(out).strip()

    headers = []
    for line in raw.splitlines():
        line = line.strip().strip("`")
        line = re.sub(r"^[-*\d.)\s]+", "", line).strip()
        if not line:
            continue
        if not HEADER_RE.match(line):
            pytest.fail(
                f"model output line is not a commit header: {line!r}\nraw output:\n{raw}"
            )
        headers.append(line)
    assert headers, f"model produced no commit headers\nraw output:\n{raw}"
    return prompt, headers


def run_bundled_checker(headers):
    if len(headers) == 1:
        argv = ["bash", str(MSG_CHECKER), headers[0]]
    else:
        argv = ["bash", str(PLAN_CHECKER), *headers]
    proc = subprocess.run(argv, cwd=SKILL_DIR, capture_output=True, text=True)
    assert proc.returncode == 0, (
        f"bundled checker rejected the plan (exit {proc.returncode})\n"
        f"headers: {headers}\nstderr: {proc.stderr.strip()}"
    )


# --- tests -----------------------------------------------------------------


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s["id"])
def test_skill_scenario(scenario):
    prompt, headers = draft_commits(scenario["scenario"])

    lo, hi = scenario["expected_commits"]
    assert lo <= len(headers) <= hi, (
        f"{scenario['id']}: expected {lo}..{hi} commits, got {len(headers)}: {headers}"
    )

    run_bundled_checker(headers)

    test_case = LLMTestCase(
        input=prompt,
        actual_output="\n".join(headers),
        expected_output=scenario["reference_plan"],
    )
    assert_test(test_case, metrics())
