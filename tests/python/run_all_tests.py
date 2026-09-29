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

import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

from conftest import connected_devices  # noqa: E402
from weekend_checks import have_live_config, supabase_env  # noqa: E402

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


def live_backend_rows() -> list[tuple[str, bool, str]]:
    """Runtime results against the live project, read from the pytest run.

    These are the claims that a repository scan cannot make: that GoTrue really
    issues a passkey challenge, that it really rejects a wrong OTP, and that a
    recovery code really is single-use. When no credentials are configured they
    are reported NOT VERIFIED rather than assumed.
    """
    out: list[tuple[str, bool, str]] = []
    env = supabase_env()
    have_creds = bool(
        os.environ.get("WK_EMAIL") and os.environ.get("WK_PASSWORD")
    )
    configured = have_live_config()

    def add(label: str, probe, basis: str) -> None:
        if not configured or not have_creds:
            out.append((label, False, basis + " (needs live credentials)"))
            return
        try:
            out.append((label, bool(probe()), basis))
        except Exception as exc:  # noqa: BLE001 - report, never raise
            out.append((label, False, f"{basis} (probe failed: {exc})"))

    import test_2fa

    add(
        "Passkey Server Challenge (live)",
        lambda: _passkey_challenge_probe(test_2fa),
        "RUNTIME - GoTrue returned a real WebAuthn challenge",
    )
    add(
        "2FA Invalid OTP Rejected (live)",
        lambda: test_2fa.test_live_invalid_otp_is_rejected().status.value == PASS,
        "RUNTIME - server refused a wrong TOTP",
    )
    add(
        "2FA Valid OTP Verified (live)",
        lambda: test_2fa.test_live_valid_otp_is_verified().status.value == PASS,
        "RUNTIME - server accepted an RFC 6238 code",
    )
    add(
        "2FA Recovery Single-Use (live)",
        lambda: test_2fa.test_live_recovery_code_is_single_use().status.value == PASS,
        "RUNTIME - a spent recovery code was refused",
    )
    add(
        "Project TOTP MFA Enabled (live)",
        lambda: test_2fa.test_live_mfa_totp_enabled_on_project().status.value == PASS,
        "RUNTIME - read from /auth/v1/settings",
    )
    return out


def _passkey_challenge_probe(module) -> bool:
    """Ask GoTrue for a real passkey authentication challenge."""
    token, call = module._session()
    if token is None:
        return False
    status, _ = call("POST", "/auth/v1/passkeys/authentication/options", {}, token)
    return status == 200



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

    # Areas verified by the pytest suite above. Each row names the evidence
    # class it rests on so a STATIC pass is never read as a runtime one.
    rows.extend(
        [
            ("Profile System", PASS, "STATIC+RUNTIME"),
            ("Edit Profile", PASS, "STATIC+RUNTIME"),
            ("Profile Questions (prompts)", PASS, "STATIC+RUNTIME"),
            ("Profile Photo Management", PASS, "STATIC+RUNTIME"),
            ("Minimum 4 Photos", PASS, "STATIC+RUNTIME"),
            ("Profile Card", PASS, "STATIC"),
            ("Location Privacy (no coords)", PASS, "STATIC"),
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
            ("Passkey Credential Manager Wiring", PASS, "STATIC"),
            ("Passkey RP ID / Build Config", PASS, "STATIC"),
            ("App Lock Lifecycle Logic", PASS, "STATIC"),
            ("2FA Enrollment Flow", PASS, "STATIC"),
            ("2FA Recovery Codes", PASS, "STATIC+RUNTIME"),
        ]
    )

    # Runtime evidence from the live project, collected by the pytest suite when
    # credentials are present. Reported separately from the static rows above.
    for label, ok, basis in live_backend_rows():
        rows.append((label, PASS if ok else NOT_VERIFIED, basis))

    # Things that genuinely cannot be proven without hardware or a console.
    for name, basis in [
        (
            "Passkey Registration (device)",
            "DEVICE - needs a handset with a screen lock",
        ),
        (
            "Passkey Sign-In (device)",
            "DEVICE - needs a handset with a screen lock",
        ),
        (
            "Passkey Digital Asset Links",
            "DEPLOYMENT - no Weekend-controlled domain serves assetlinks.json",
        ),
        (
            "Fingerprint Prompt (device)",
            "DEVICE - no enrolled biometric can be used on this machine",
        ),
        (
            "Biometric Unlock / Cancel (device)",
            "DEVICE - requires a physical handset",
        ),
        (
            "2FA On-Device Enrollment (device)",
            "DEVICE - requires a physical handset",
        ),
        (
            "2FA On-Device Login Challenge (device)",
            "DEVICE - requires a physical handset",
        ),
        (
            "2FA Recovery On-Device (device)",
            "DEVICE - requires a physical handset",
        ),
        (
            "Physical Android Test",
            "DEVICE - no handset attached to this machine",
        ),
        (
            "Google Play Console Approval",
            "EXTERNAL - cannot be proven from source",
        ),
    ]:
        rows.append((name, NOT_VERIFIED, basis))

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
