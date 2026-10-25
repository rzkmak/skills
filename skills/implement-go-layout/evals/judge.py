#!/usr/bin/env python3
"""Zero-dependency judge for the implement-go-layout skill.

Reads SKILL.md and evals/dataset.jsonl, then for every case:
  * asserts each required_skill_terms entry appears in SKILL.md, and
  * executes the case's checker script and compares the exit code
    against expected_exit_code.

A case may define:
  input          — single string argument (default checker: check_snippet.sh)
  input_args     — list of string arguments (for multi-argument checkers)
  checker        — script name under scripts/ (default: check_snippet.sh)

Exits 0 only when every case passes.
"""

import json
import subprocess
import sys
from pathlib import Path

EVALS_DIR = Path(__file__).resolve().parent
SKILL_DIR = EVALS_DIR.parent
SKILL_MD = SKILL_DIR / "SKILL.md"
DATASET = EVALS_DIR / "dataset.jsonl"


def load_cases():
    cases = []
    with DATASET.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                cases.append(json.loads(line))
    return cases


def build_argv(case):
    checker = SKILL_DIR / "scripts" / case.get("checker", "check_snippet.sh")
    if "input_args" in case:
        return [str(checker)] + [str(arg) for arg in case["input_args"]]
    return [str(checker), case.get("input", "")]


def main():
    skill_md = SKILL_MD.read_text(encoding="utf-8")
    cases = load_cases()

    failures = 0
    for case in cases:
        reasons = []

        for term in case.get("required_skill_terms", []):
            if term not in skill_md:
                reasons.append(f"SKILL.md is missing required term {term!r}")

        proc = subprocess.run(build_argv(case), capture_output=True, text=True)
        if proc.returncode != case["expected_exit_code"]:
            reasons.append(
                f"expected exit code {case['expected_exit_code']}, "
                f"got {proc.returncode} (stderr: {proc.stderr.strip() or '<none>'})"
            )

        if reasons:
            failures += 1
            print(f"[FAIL] {case['id']}")
            for reason in reasons:
                print(f"       - {reason}")
        else:
            print(f"[PASS] {case['id']}")

    print(f"{len(cases) - failures}/{len(cases)} cases passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
