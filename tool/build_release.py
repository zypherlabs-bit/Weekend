"""Build the release APK with credentials injected from .env.

    python tool/build_release.py

Reads SUPABASE_URL / SUPABASE_ANON_KEY from the git-ignored .env and passes
them as --dart-define, so no credential is ever written to a build script,
a CI log or a tracked file.

Usage:
    python tool/build_release.py            # build + report
    python tool/build_release.py --sha256   # also print the release checksum
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = PROJECT_ROOT / ".env"

REQUIRED = ["SUPABASE_URL", "SUPABASE_ANON_KEY"]


def load_env(path: Path = ENV_FILE) -> dict[str, str]:
    """Parse a simple KEY=VALUE .env file.

    Deliberately minimal: a dotenv dependency would be another supply-chain
    surface for a build script that handles credentials.
    """
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def dart_defines(env: dict[str, str]) -> list[str]:
    missing = [k for k in REQUIRED if not env.get(k)]
    if missing:
        raise SystemExit(
            f"Missing required credentials in .env: {', '.join(missing)}\n"
            "Add them before building a release APK."
        )
    return [
        f"--dart-define={key}={env[key]}" for key in REQUIRED
    ]


def flutter_command() -> list[str] | None:
    """Locate the Flutter SDK.

    ``flutter`` is on the developer's interactive PATH but not necessarily on
    the PATH an IDE or scheduled process inherits, and a missing SDK must
    produce a clear message rather than a WinError.
    """
    found = shutil.which("flutter")
    if found:
        return [found]

    for parent in [PROJECT_ROOT, *PROJECT_ROOT.parents]:
        for candidate in (
            parent / "flutter" / "bin" / "flutter.bat",
            parent / "flutter" / "bin" / "flutter",
        ):
            if candidate.exists():
                return [str(candidate)]
    return None


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    print(f"$ {' '.join(redact(c) for c in cmd)}")
    return subprocess.run(cmd, cwd=str(PROJECT_ROOT), **kwargs)


def redact(arg: str) -> str:
    """Never echo a credential value back to the console."""
    for key in REQUIRED:
        if arg.startswith(f"--dart-define={key}="):
            return f"--dart-define={key}=***"
    return arg


def version_name() -> str:
    pubspec = (PROJECT_ROOT / "pubspec.yaml").read_text(encoding="utf-8-sig")
    m = re.search(r"^version:\s*(\S+?)\+", pubspec, re.MULTILINE)
    return m.group(1) if m else "0.0.0"


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sha256", action="store_true", help="print the checksum")
    args = parser.parse_args()

    env = load_env()
    defines = dart_defines(env)

    flutter = flutter_command()
    if flutter is None:
        raise SystemExit(
            "Flutter SDK not found. Install Flutter or add it to PATH, "
            "then re-run this script."
        )

    version = version_name()
    print(f"Weekend v{version} - release build")
    print()

    result = run(
        [*flutter, "build", "apk", "--release", *defines],
        capture_output=True,
        text=True,
    )
    if result.stdout:
        print(result.stdout)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        print()
        print("BUILD FAILED")
        return result.returncode

    apk = PROJECT_ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    if not apk.exists():
        print("BUILD FAILED: the APK was not produced")
        return 1

    size_mb = apk.stat().st_size / (1024 * 1024)
    print(f"APK   : {apk}")
    print(f"Size  : {size_mb:.1f} MB")

    if args.sha256:
        digest = sha256_of(apk)
        print(f"SHA256: {digest}")

        # Write the checksum file next to the release assets so the value can
        # be verified by anyone who downloads the APK.
        target = PROJECT_ROOT / f"Weekend-v{version}-release.apk.sha256"
        target.write_text(f"{digest}  Weekend-v{version}-release.apk\n", encoding="utf-8")
        print(f"Wrote : {target.name}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
