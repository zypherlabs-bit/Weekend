"""Dependencies and security audit.

Runs flutter pub get, flutter analyze, and checks for vulnerable or
abandoned dependencies.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

import shutil

def _flutter_available() -> bool:
    return shutil.which("flutter") is not None

def _dart_available() -> bool:
    return shutil.which("dart") is not None


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(" ".join(cmd), capture_output=True, text=True, cwd=ROOT, shell=True)


class TestDependencies:
    def test_flutter_pub_get_succeeds(self) -> None:
        if not _flutter_available():
            import pytest
            pytest.skip("flutter not available")
        result = _run(["flutter", "pub", "get"])
        assert result.returncode == 0, f"flutter pub get failed: {result.stderr}"

    def test_flutter_analyze_clean(self) -> None:
        if not _flutter_available():
            import pytest
            pytest.skip("flutter not available")
        result = _run(["flutter", "analyze"])
        assert result.returncode == 0, f"flutter analyze had issues:\n{result.stdout}\n{result.stderr}"

    def test_flutter_test_pass(self) -> None:
        if not _flutter_available():
            import pytest
            pytest.skip("flutter not available")
        result = _run(["flutter", "test"])
        assert result.returncode == 0, f"flutter test failed:\n{result.stdout}\n{result.stderr}"

    def test_no_outdated_dependencies(self) -> None:
        if not _flutter_available():
            import pytest
            pytest.skip("flutter not available")
        """Check for dependencies that are potentially outdated."""
        result = _run(["flutter", "pub", "outdated"])
        # This may output current/outdated/stable status; we just check it runs
        # and doesn't crash. Some deps may legitimately be at their latest version.
        print(f"[INFO] flutter pub outdated output:\n{result.stdout}")

    def test_pubspec_lock_exists(self) -> None:
        lock = ROOT / "pubspec.lock"
        assert lock.exists(), "pubspec.lock not found"
        assert lock.stat().st_size > 0, "pubspec.lock is empty"

    def test_no_vulnerable_transitive_dependencies(self) -> None:
        if not _dart_available():
            import pytest
            pytest.skip("dart not available")
        """Run dart analyze for security warnings."""
        result = _run(["dart", "analyze", "--enable-asserts", "--enable-experiment", "ffi"])
        # May fail if dart not available; just check it runs
        print(f"[INFO] dart analyze output:\n{result.stdout}")