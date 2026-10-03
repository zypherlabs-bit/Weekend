"""Weekend - shared helpers for the Python verification suite.

The suite separates three kinds of evidence, and the distinction is the whole
point of this package:

``STATIC``
    Something proved by reading the repository (a file exists, a migration
    contains a policy, a source file calls a given API). Honest, but it says
    nothing about runtime behaviour.

``RUNTIME``
    Something actually executed and produced a result. Only produced by tests
    that talk to the live Supabase project or run the Dart/Flutter tooling.

``DEVICE``
    Something that can only be confirmed on real Android hardware. The suite
    NEVER reports these as PASS. They are always ``NOT VERIFIED`` unless a
    signed evidence file produced by an actual device run is present.

Every result carries one of :class:`Status` values. A test that cannot prove
its claim must return :attr:`Status.NOT_VERIFIED` rather than guessing.
"""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

# tests/python/ -> repository root
REPO_ROOT = Path(__file__).resolve().parents[2]


class Status(str, Enum):
    """Outcome vocabulary shared by every check in the suite."""

    PASS = "PASS"
    FAIL = "FAIL"
    NOT_VERIFIED = "NOT VERIFIED"


class Evidence(str, Enum):
    """How a result was established."""

    STATIC = "STATIC"
    RUNTIME = "RUNTIME"
    DEVICE = "DEVICE"


@dataclass
class CheckResult:
    """A single named check and its honest outcome."""

    name: str
    status: Status
    evidence: Evidence
    detail: str = ""
    children: list["CheckResult"] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return self.status is Status.PASS

    def line(self) -> str:
        return f"{self.name:<34} {self.status.value:<14} {self.detail}"


def read_text(path: Path) -> str:
    """Read a file, returning "" when it does not exist."""
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except (OSError, UnicodeDecodeError):
        return ""


def dart_sources(subdir: str = "lib") -> list[Path]:
    return sorted((REPO_ROOT / subdir).rglob("*.dart"))


def migrations() -> list[Path]:
    return sorted((REPO_ROOT / "supabase" / "migrations").glob("*.sql"))


def migration_text() -> str:
    """Concatenate every migration into one searchable blob.

    Later migrations supersede earlier ones, so the concatenation reflects the
    final state of the schema rather than any single file.
    """
    return "\n".join(read_text(p) for p in migrations())


def latest_migration_text() -> str:
    """Concatenate every migration into one searchable blob, newest last.

    Later migrations supersede earlier ones, so the concatenation reflects the
    state the schema is actually in after every migration has run.

    This deliberately mirrors :func:`conftest.latest_migration_text`, which has
    always had this behaviour. Returning only the highest-numbered file made
    every check that asserts on schema introduced by an EARLIER migration fail
    as soon as a new migration was added - the checks were correct, the helper
    was too narrow.
    """
    return migration_text()



# ---------------------------------------------------------------------------
# Live-backend access
# ---------------------------------------------------------------------------

def supabase_env() -> dict[str, str]:
    """Load SUPABASE_URL / SUPABASE_ANON_KEY from the git-ignored .env.

    Values are read into memory only; nothing here prints, logs or writes
    them. Returns an empty dict when the file is absent.
    """
    out: dict[str, str] = {}
    for line in read_text(REPO_ROOT / ".env").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        out[key.strip()] = value.strip()
    return out


def have_live_config() -> bool:
    """True when a real (non-placeholder) live project is configured."""
    env = supabase_env()
    url = env.get("SUPABASE_URL", "")
    key = env.get("SUPABASE_ANON_KEY", "")
    return bool(
        url
        and key
        and "your-project-ref" not in url
        and url != "public-anon-key-here"
        and key != "public-anon-key-here"
    )


def management_token() -> str | None:
    """Supabase Management API token, if available in this environment.

    Checked in the environment first, then the conventional temp file used by
    this repository's tooling. Never printed.
    """
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if token:
        return token
    import tempfile

    fallback = Path(tempfile.gettempdir()) / "sbp_token.txt"
    if fallback.exists():
        return read_text(fallback).strip() or None
    return None


# ---------------------------------------------------------------------------
# Device evidence
# ---------------------------------------------------------------------------

#: Written by a real on-device test run. Absent means nothing was verified.
DEVICE_EVIDENCE_FILE = REPO_ROOT / "docs" / "device_test_evidence.json"


def device_evidence() -> dict:
    """Load on-device test evidence, or {} when no device run is recorded.

    The suite treats a missing file as proof that no physical-device test was
    performed, which is the honest default.
    """
    import json

    if not DEVICE_EVIDENCE_FILE.exists():
        return {}
    try:
        return json.loads(read_text(DEVICE_EVIDENCE_FILE))
    except (ValueError, TypeError):
        return {}


def device_connected() -> bool:
    """True when a PHYSICAL Android device is attached via adb.

    Emulators are explicitly excluded: the specification requires physical
    hardware for passkey, biometric and photo-picker verification, and an
    emulator's software fingerprint is not evidence for any of them.
    """
    code, out = run_tool(["adb", "devices"], timeout=30)
    if code != 0:
        return False
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 2 or parts[1] != "device":
            continue
        serial = parts[0]
        if serial.startswith("emulator-"):
            continue
        # Cross-check ro.kernel.qemu: emulator serials are not always
        # prefixed, but this property is set on every emulator image.
        qcode, qout = run_tool(
            ["adb", "-s", serial, "shell", "getprop", "ro.kernel.qemu"], timeout=30
        )
        if qcode == 0 and qout.strip() == "1":
            continue
        return True
    return False


# ---------------------------------------------------------------------------
# Secret scanning
# ---------------------------------------------------------------------------

def secret_scan_patterns() -> list[tuple[str, str]]:
    """(label, regex) pairs used by the security scan.

    These match the *shape* of a committed secret. Documentation and example
    files are filtered out by the caller so a
    ``SUPABASE_SERVICE_ROLE_KEY=`` line in a README is not reported as a leak.
    """
    return [
        ("service_role", r"service_role"),
        ("SUPABASE_SERVICE_ROLE_KEY", r"SUPABASE_SERVICE_ROLE_KEY"),
        ("private_key", r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
        ("client_secret", r"client_secret\s*[:=]"),
        ("password_assignment", r"password\s*=\s*['\"][^'\"]{6,}['\"]"),
        ("secret_assignment", r"secret\s*=\s*['\"][^'\"]{8,}['\"]"),
        ("aws_access_key", r"AKIA[0-9A-Z]{16}"),
        ("gh_token", r"gh[pousr]_[A-Za-z0-9]{20,}"),
    ]


#: Matches a real Supabase anon/publishable key or Management API PAT.
SECRET_VALUE_RE = re.compile(r"(eyJ[A-Za-z0-9_-]{40,}|sbp_[A-Za-z0-9]{30,})")


def run_tool(cmd: list[str], timeout: int = 180) -> tuple[int, str]:
    """Run a command, returning (exit_code, combined_output).

    Never raises: a missing tool is reported as a non-zero exit so the caller
    can turn it into a NOT VERIFIED result instead of crashing the suite.
    """
    try:
        proc = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
            shell=os.name == "nt",
        )
        return proc.returncode, (proc.stdout or "") + (proc.stderr or "")
    except FileNotFoundError:
        return 127, f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout}s: {' '.join(cmd)}"
