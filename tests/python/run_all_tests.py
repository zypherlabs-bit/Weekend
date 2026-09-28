#!/usr/bin/env python3
"""Weekend - run the complete Python verification suite and print a report.

Usage
-----
    python tests/python/run_all_tests.py
    python tests/python/run_all_tests.py --skip-slow   # skip toolchain probes
    python tests/python/run_all_tests.py --json out.json

Every check reports exactly one of PASS, FAIL or NOT VERIFIED. A NOT VERIFIED
result is the correct answer whenever the evidence needed to make a claim does
not exist - for example "no physical device is attached". It is never upgraded
to PASS on the basis of a file existing, a build succeeding, or a package
being installed.

Exit code is 0 only when no check FAILED. NOT VERIFIED does not fail the run;
it is reported prominently so a reader cannot mistake it for success.
"""

from __future__ import annotations

import argparse
import importlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from weekend_checks import CheckResult, Evidence, Status  # noqa: E402

MODULES = [
    "test_project_structure",
    "test_security",
    "test_passkey",
    "test_location",
    "test_filter_logic",
    "test_navigation",
    "test_supabase",
    "test_release",
]

#: Checks that shell out to the Flutter toolchain and are therefore slow.
SLOW_MARKERS = ("flutter analyze", "flutter test")


def collect(skip_slow: bool) -> tuple[list[CheckResult], list[str]]:
    """Run every check module and collect its CheckResult objects."""
    results: list[CheckResult] = []
    errors: list[str] = []

    for module_name in MODULES:
        try:
            module = importlib.import_module(module_name)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{module_name}: import failed: {exc}")
            results.append(
                CheckResult(
                    name=module_name,
                    status=Status.FAIL,
                    evidence=Evidence.STATIC,
                    detail=f"import error: {type(exc).__name__}",
                )
            )
            continue

        for attr in sorted(dir(module)):
            if not attr.startswith("test_"):
                continue
            func = getattr(module, attr)
            if not callable(func):
                continue
            label = attr.removeprefix("test_").replace("_", " ").capitalize()

            if skip_slow and any(m in (func.__doc__ or "") for m in SLOW_MARKERS):
                results.append(
                    CheckResult(
                        name=label,
                        status=Status.NOT_VERIFIED,
                        evidence=Evidence.RUNTIME,
                        detail="skipped (--skip-slow)",
                    )
                )
                continue
            try:
                out = func()
            except AssertionError as exc:
                results.append(
                    CheckResult(
                        name=label,
                        status=Status.FAIL,
                        evidence=Evidence.RUNTIME,
                        detail=f"assertion failed: {str(exc)[:70]}",
                    )
                )
                continue
            except Exception as exc:  # noqa: BLE001
                results.append(
                    CheckResult(
                        name=label,
                        status=Status.FAIL,
                        evidence=Evidence.STATIC,
                        detail=f"{type(exc).__name__}: {str(exc)[:60]}",
                    )
                )
                continue

            if isinstance(out, CheckResult):
                results.append(out)
            else:
                results.append(
                    CheckResult(
                        name=label,
                        status=Status.PASS,
                        evidence=Evidence.RUNTIME,
                        detail="assertion passed",
                    )
                )

    return results, errors


def render(results: list[CheckResult], errors: list[str]) -> str:
    """Format the report in the shape the specification requires."""
    lines: list[str] = []
    lines.append("=" * 60)
    lines.append("WEEKEND PROJECT VERIFICATION")
    lines.append("=" * 60)

    device: list[CheckResult] = []
    for result in results:
        if result.evidence is Evidence.DEVICE:
            device.append(result)
            continue
        lines.append(f"{result.name:<34} {result.status.value:<14} {result.detail}")

    if errors:
        lines.append("")
        lines.append("ERRORS")
        lines.extend(f"  {e}" for e in errors)

    if device:
        lines.append("")
        for result in device:
            lines.append(f"{result.name:<34} {result.status.value:<14} {result.detail}")

    passed = sum(1 for r in results if r.status is Status.PASS)
    failed = sum(1 for r in results if r.status is Status.FAIL)
    unverified = sum(1 for r in results if r.status is Status.NOT_VERIFIED)

    lines.append("")
    lines.append("=" * 60)
    lines.append("RESULT")
    lines.append("=" * 60)
    lines.append(f"PASS: {passed}   FAIL: {failed}   NOT VERIFIED: {unverified}")
    if unverified:
        lines.append("")
        lines.append(
            "NOT VERIFIED means the evidence required to make that claim does "
            "not exist."
        )
        lines.append("It is NOT a pass. Do not report those features as working.")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Weekend verification suite")
    parser.add_argument(
        "--skip-slow",
        action="store_true",
        help="skip checks that invoke the Flutter toolchain",
    )
    parser.add_argument("--json", help="write machine-readable results to a file")
    args = parser.parse_args()

    results, errors = collect(args.skip_slow)
    print(render(results, errors))

    if args.json:
        Path(args.json).write_text(
            json.dumps(
                {
                    "results": [
                        {
                            "name": r.name,
                            "status": r.status.value,
                            "evidence": r.evidence.value,
                            "detail": r.detail,
                        }
                        for r in results
                    ],
                    "errors": errors,
                },
                indent=2,
            ),
            encoding="utf-8",
        )

    return 1 if any(r.status is Status.FAIL for r in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
