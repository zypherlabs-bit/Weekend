"""Shared helpers for the Weekend verification suite.

Every check is classified as one of:

* ``STATIC``   - repository / configuration inspection (fast, always possible)
* ``RUNTIME``  - executes real logic in-process (pure Dart/Python reimplementation
                 or a live backend call)
* ``DEVICE``   - requires a physical Android handset

The distinction matters: a static pass proves the code is *written*, never
that a phone *ran* it. Reports keep the two apart.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Iterable, Sequence

PROJECT_ROOT = Path(__file__).resolve().parents[2]


class Status(str, Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    NOT_VERIFIED = "NOT VERIFIED"


class Evidence(str, Enum):
    STATIC = "STATIC"
    RUNTIME = "RUNTIME"
    DEVICE = "DEVICE"


@dataclass
class Check:
    category: str
    name: str
    status: Status
    evidence: Evidence
    detail: str = ""

    @property
    def counts_as_pass(self) -> bool:
        return self.status is Status.PASS


def read(path: Path) -> str:
    """Read a text file, tolerating a UTF-8 BOM and CRLF endings."""
    return path.read_text(encoding="utf-8-sig", errors="replace")


def read_optional(path: Path) -> str | None:
    return read(path) if path.exists() else None


def lib_files(root: Path = PROJECT_ROOT) -> list[Path]:
    """Every tracked Dart file under lib/, ignoring build output."""
    return [
        p
        for p in (root / "lib").rglob("*.dart")
        if ".dart_tool" not in p.parts and "build" not in p.parts
    ]


def migration_files(root: Path = PROJECT_ROOT) -> list[Path]:
    return sorted((root / "supabase" / "migrations").glob("*.sql"))


def latest_migration_text(root: Path = PROJECT_ROOT) -> str:
    """Concatenate every migration, newest last.

    Later migrations redefine earlier functions, so the effective definition
    of an RPC is the one in the highest-numbered file that mentions it.
    """
    return "\n".join(read(p) for p in migration_files(root))


def strip_sql_comments(sql: str) -> str:
    """Remove ``--`` comments so a doc-comment cannot satisfy a code check."""
    return re.sub(r"--[^\n]*", "", sql)


def function_body(sql: str, name: str) -> str | None:
    """Return the body of the LAST definition of ``name`` in ``sql``.

    Finds ``create or replace function <name>`` and returns everything from
    the opening ``$$``/``$fn$`` delimiter to its match, so the caller sees
    the definition that would actually be in force after all migrations ran.
    """
    pattern = re.compile(
        r"create\s+or\s+replace\s+function\s+(?:public\.)?"
        + re.escape(name)
        + r"\s*\(",
        re.IGNORECASE,
    )
    matches = list(pattern.finditer(sql))
    if not matches:
        return None

    start = matches[-1].start()
    # Locate the body delimiter that follows the signature.
    dollar = re.search(r"\$\$(.*?)\$\$", sql[start:], re.DOTALL)
    if dollar:
        return dollar.group(1)
    tagged = re.search(r"\$([A-Za-z_]\w*)\$.*?\$\1\$", sql[start:], re.DOTALL)
    if tagged:
        return tagged.group(0)
    return sql[start:]


def dart_defines_dart(source: str) -> bool:
    """True if the Dart source references the given String.fromEnvironment key."""
    return f"String.fromEnvironment('{key}')" in source or (
        f'String.fromEnvironment("{key}")' in source
    )


def has_dart_defines(source: str, key: str) -> bool:
    return dart_defines_dart(source)


def run_command(args: Sequence[str], cwd: Path = PROJECT_ROOT, timeout: int = 600):
    """Run a command, returning (returncode, combined_output). Never raises."""
    try:
        proc = subprocess.run(
            list(args),
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=timeout,
            shell=False,
        )
    except FileNotFoundError:
        return 127, f"command not found: {args[0]}"
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout}s: {' '.join(args)}"
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def adb_path() -> Path | None:
    """Locate adb via the SDK path in android/local.properties, else PATH."""
    local_props = PROJECT_ROOT / "android" / "local.properties"
    if local_props.exists():
        m = re.search(r"sdk\.dir=(.*)", read(local_props))
        if m:
            candidate = Path(m.group(1).strip().replace("\\\\", "\\"))
            adb = candidate / "platform-tools" / "adb.exe"
            if adb.exists():
                return adb
    from shutil import which

    found = which("adb")
    return Path(found) if found else None


def connected_devices() -> list[str]:
    """Serial numbers of attached Android devices ([] when none)."""
    adb = adb_path()
    if adb is None:
        return []
    code, out = run_command([str(adb), "devices"], timeout=60)
    if code != 0:
        return []
    devices = []
    for line in out.splitlines()[1:]:
        line = line.strip()
        if not line or line.startswith("*"):
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])
    return devices


def any_contains(haystack: str, needles: Iterable[str]) -> bool:
    return any(n in haystack for n in needles)
