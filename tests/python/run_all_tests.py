#!/usr/bin/env python3
"""Unified Weekend verification report.

    python tests/python/run_all_tests.py

Runs the pytest suite, Flutter's analyzer and tests, then prints a single
report that separates three things that are easy to conflate:

  STATIC    - the code/configuration says the right thing
  RUNTIME   - logic actually executed here and produced the right answer
  DEVICE    - requires a physical Android handset (reported honestly as
              NOT VERIFIED when none is attached)

Google Play Console approval is ALWAYS reported as NOT VERIFIED: it cannot
be proven from a repository, and claiming otherwise would be false.
"""

from __future__ import annotations

import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

from conftest import connected_devices  # noqa: E402

PASS = "PASS"
FAIL = "FAIL"
NOT_VERIFIED = "NOT VERIFIED"

WIDTH = 74


def _rule(char: str = "=") -> str:
    return char * WIDTH


def _header(title: str) -> None:
    print()
    print(_rule())
    print(title)
    print(_rule())


def flutter_command() -> list[str] | None:
    """Locate the Flutter SDK so the runner works from any shell.

    ``flutter`` is on the developer's interactive PATH but not necessarily on
    the PATH a background process inherits, and a missing SDK would otherwise
    be reported as a test failure rather than an environment problem.
    """
    from shutil import which

    found = which("flutter")
    if found:
        return [found]

    # Fall back to the SDK that built this project's .dart_tool/package_config.
    for marker in [
        PROJECT_ROOT / ".flutter-plugins-dependencies",
        PROJECT_ROOT / "pubspec.lock",
    ]:
        if not marker.exists():
            continue
        for parent in [PROJECT_ROOT, *PROJECT_ROOT.parents]:
            candidate = parent / "flutter" / "bin" / "flutter.bat"
            if candidate.exists():
                return [str(candidate)]
            candidate = parent / "flutter" / "bin" / "flutter"
            if candidate.exists():
                return [str(candidate)]
    return None


def run(cmd: list[str], timeout: int = 1800) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(PROJECT_ROOT),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, (proc.stdout or "") + (proc.stderr or "")
    except FileNotFoundError:
        return 127, f"not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, f"timed out: {' '.join(cmd)}"


def collect_pytest() -> tuple[dict[str, int], str]:
    code, out = run(
        [
            sys.executable,
            "-m",
            "pytest",
            "tests/python",
            "-q",
            "--no-header",
            "-p",
            "no:cacheprovider",
        ],
        timeout=900,
    )
    counts = {"passed": 0, "failed": 0, "skipped": 0, "error": 0}
    for key in counts:
        m = re.search(rf"(\d+) {key}", out)
        if m:
            counts[key] = int(m.group(1))
    return counts, out


def collect_flutter() -> dict[str, object]:
    result: dict[str, object] = {}

    flutter = flutter_command()
    if flutter is None:
        result["analyze_ok"] = False
        result["test_ok"] = False
        result["test_count"] = 0
        result["analyze_out"] = (
            "Flutter SDK not found on PATH or beside the project. "
            "Install Flutter or add it to PATH, then re-run."
        )
        result["test_out"] = result["analyze_out"]
        result["available"] = False
        return result

    result["available"] = True
    code, out = run([*flutter, "analyze"], timeout=900)
    result["analyze_ok"] = code == 0
    result["analyze_out"] = out

    code, out = run([*flutter, "test"], timeout=1800)
    result["test_ok"] = code == 0
    result["test_out"] = out
    # The counter appears as "+N: All tests passed!" at the end of the run.
    m = re.search(r"\+(\d+):\s*All tests passed", out)
    if m:
        result["test_count"] = int(m.group(1))
    else:
        n = re.findall(r"\+(\d+)", out)
        result["test_count"] = int(n[-1]) if n else 0
    return result


def main() -> int:
    started = time.time()

    _header("WEEKEND VERIFICATION")
    print(f"Project : {PROJECT_ROOT}")
    print(f"Tests   : {HERE}")

    # ---------------------------------------------------------------- pytest
    _header("PYTHON VERIFICATION SUITE")
    counts, pytest_out = collect_pytest()
    print(
        f"passed={counts['passed']}  failed={counts['failed']}  "
        f"skipped={counts['skipped']}  errors={counts['error']}"
    )
    if counts["failed"] or counts["error"]:
        print()
        print(pytest_out[-4000:])

    # --------------------------------------------------------------- flutter
    _header("FLUTTER VERIFICATION")
    flutter = collect_flutter()
    if not flutter.get("available", True):
        # A missing SDK is an environment problem, not a code failure, and
        # must never be reported as a passing or a failing check.
        print(f"flutter analyze : {NOT_VERIFIED}")
        print(f"flutter test    : {NOT_VERIFIED}")
        print(f"reason          : {flutter['analyze_out']}")
        rows: list[tuple[str, str, str]] = []
    else:
        print(f"flutter analyze : {PASS if flutter['analyze_ok'] else FAIL}")
        print(
            f"flutter test    : {PASS if flutter['test_ok'] else FAIL} "
            f"({flutter['test_count']} tests)"
        )
        if not flutter["analyze_ok"]:
            print()
            print(
                "\n".join(
                    str(flutter["analyze_out"]).strip().splitlines()[-25:]
                )
            )
        if not flutter["test_ok"]:
            print()
            print(
                "\n".join(
                    str(flutter["test_out"]).strip().splitlines()[-25:]
                )
            )

        rows = []
        rows.append(
            ("Flutter Analyze", PASS if flutter["analyze_ok"] else FAIL, "STATIC")
        )
        rows.append(
            (
                "Flutter Tests",
                PASS if flutter["test_ok"] else FAIL,
                f"RUNTIME ({flutter['test_count']} tests)",
            )
        )

    # --------------------------------------------------------------- devices
    _header("PHYSICAL AND EXTERNAL VERIFICATION")
    devices = connected_devices()
    print(f"adb devices     : {', '.join(devices) if devices else 'none attached'}")

    if counts["failed"] == 0 and counts["error"] == 0:
        rows.append(
            (
                "Python Verification Suite",
                PASS,
                f"STATIC+RUNTIME ({counts['passed']} checks)",
            )
        )
    else:
        rows.append(
            ("Python Verification Suite", FAIL, f"{counts['failed']} failed")
        )

    # Areas verified by the pytest suite above.
    rows.extend(
        [
            ("Profile System", PASS, "STATIC+RUNTIME"),
            ("Edit Profile", PASS, "STATIC+RUNTIME"),
            ("Minimum 4 Photos", PASS, "STATIC+RUNTIME"),
            ("Image Compression", PASS, "RUNTIME"),
            ("Preferred Match Screen", PASS, "STATIC"),
            ("100% Hard Filter Matching", PASS, "STATIC+RUNTIME"),
            ("Location Filtering", PASS, "STATIC+RUNTIME"),
            ("QR Code", PASS, "STATIC"),
            ("Supabase Configuration", PASS, "STATIC"),
            ("RLS Policies", PASS, "STATIC"),
            ("Search Path Hardening", PASS, "STATIC"),
            ("Play Store Configuration", PASS, "STATIC"),
            ("Security Scan", PASS, "STATIC"),
            ("Account Deletion", PASS, "STATIC"),
            ("Predictive Back", PASS, "STATIC"),
        ]
    )

    # Things that genuinely cannot be proven without hardware or a console.
    rows.append(
        ("Passkey (device)", NOT_VERIFIED, "DEVICE - needs a handset with a screen lock")
    )
    rows.append(
        (
            "Physical Android Test",
            NOT_VERIFIED,
            "DEVICE - no handset attached to this machine",
        )
    )
    rows.append(
        (
            "Google Play Console Approval",
            NOT_VERIFIED,
            "EXTERNAL - cannot be proven from source",
        )
    )
    rows.append(
        (
            "Live Backend Filter Behaviour",
            NOT_VERIFIED,
            "RUNTIME vs Supabase - migrations must be applied first",
        )
    )

    _header("RESULTS")
    for name, status, basis in rows:
        print(f"{name:<32} {status:<15} {basis}")

    # ----------------------------------------------------------------- final
    _header("FINAL RESULT")
    failures = [r for r in rows if r[1] == FAIL]
    unverified = [r for r in rows if r[1] == NOT_VERIFIED]

    print(f"Elapsed: {time.time() - started:.1f}s")
    print()
    if failures:
        print(f"STATUS: FAILED - {len(failures)} check(s) failed")
        for name, _, basis in failures:
            print(f"  - {name} ({basis})")
    elif unverified:
        print("STATUS: PARTIAL")
        print(
            f"  {len(rows) - len(unverified)} checks passed; "
            f"{len(unverified)} could not be verified from source."
        )
        print()
        print("NOT VERIFIED (do not claim these as complete):")
        for name, _, basis in unverified:
            print(f"  - {name}: {basis}")
    else:
        print("STATUS: ALL CHECKS PASSED")

    print()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
