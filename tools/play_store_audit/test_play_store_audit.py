"""Main Play Store readiness audit suite.

Runs all individual audit test modules and produces a summary report.

Usage:
    pytest tools/play_store_audit/ -v
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

# Add the tools/play_store_audit to the path so we can import modules
AUDIT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(AUDIT_DIR))


def run_tests() -> int:
    """Run all audit tests and return the exit code."""
    # Install requirements first
    print("=" * 60)
    print("Weekend - Google Play Store Readiness Audit")
    print("=" * 60)
    print()

    # Run pytest on the audit directory
    result = subprocess.run(
        [sys.executable, "-m", "pytest",
         str(AUDIT_DIR),
         "--tb=short",
         "--co", "failure"],  # concise output
        capture_output=True,
        text=True,
    )

    print(result.stdout)
    if result.stderr:
        print("STDERR:", result.stderr)

    print()
    print("=" * 60)
    if result.returncode == 0:
        print("ALL TESTS PASSED - No locally verifiable blockers found")
    else:
        print("SOME TESTS FAILED - See details above for blockers")
    print("=" * 60)

    return result.returncode


if __name__ == "__main__":
    sys.exit(run_tests())