"""Generate the Digital Asset Links statement Android Credential Manager needs.

Android only completes a WebAuthn ceremony for a relying party that is
associated with the installed app. For an APK distributed outside Google Play
that association is proved by a file served at:

    https://<relying-party-id>/.well-known/assetlinks.json

containing this app's package name and the SHA-256 of the certificate that
signed the APK. The digest is signing-key specific, so debug and release need
different statements - this script computes both from the real keystores
rather than asking anyone to copy a hex string by hand.

Usage:
    python tool/gen_assetlinks.py                  # every available key
    python tool/gen_assetlinks.py --emit-release   # paste-ready JSON

The script never fabricates a digest: an unavailable keystore is reported as
MISSING and `--emit-release` refuses to print a statement at all, rather than
emitting a placeholder that would look valid and match nothing.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import pathlib
import subprocess
import sys
from shutil import which
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android"
PACKAGE = "com.weekend.app"
MISSING = "MISSING"


def keytool() -> str:
    """Locate keytool: PATH, JAVA_HOME, then the Android Studio JBR."""
    exe = "keytool.exe" if sys.platform == "win32" else "keytool"

    found = which(exe)
    if found:
        return found

    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        candidate = pathlib.Path(java_home) / "bin" / exe
        if candidate.exists():
            return str(candidate)

    for base in (
        pathlib.Path.home() / "AppData/Local/Programs/Android Studio/jbr/bin",
        pathlib.Path("/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin"),
    ):
        candidate = base / exe
        if candidate.exists():
            return str(candidate)
    return ""


def digest_of(keystore: pathlib.Path, alias: str, storepass: str) -> str:
    """base64(SHA-256(cert DER)), unpadded - the assetlinks.json format."""
    tool = keytool()
    if not tool:
        print("  keytool not found; install a JDK or set JAVA_HOME")
        return MISSING
    try:
        out = subprocess.run(
            [
                tool,
                "-list",
                "-v",
                "-keystore",
                str(keystore),
                "-alias",
                alias,
                "-storepass",
                storepass,
            ],
            capture_output=True,
            text=True,
            timeout=60,
            check=True,
        ).stdout
    except Exception as exc:  # noqa: BLE001 - any failure means "cannot read"
        print(f"  keytool failed for {keystore}: {exc}")
        return MISSING

    # keytool prints:
    #   Certificate fingerprints:
    #            SHA1:   24:D5:...
    #            SHA256: D4:1C:...
    # The whole colon-separated run is the hex digest; splitting on ':' and
    # keeping the first field silently truncates it to a single byte.
    lines = out.splitlines()
    for i, line in enumerate(lines):
        if "Certificate fingerprints" not in line:
            continue
        for candidate in lines[i + 1 :]:
            if "SHA256" not in candidate:
                continue
            hex_digest = candidate.split(":", 1)[1].strip().replace(":", "")
            if not hex_digest:
                continue
            return base64.b64encode(bytes.fromhex(hex_digest)).decode().rstrip("=")
    return MISSING


def release_store() -> tuple[pathlib.Path | None, str, str]:
    """(keystore, alias, storepass) from android/key.properties, or Nones."""
    props = ANDROID / "key.properties"
    if not props.exists():
        return None, "", ""
    values: dict[str, str] = {}
    for line in props.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            values[k.strip()] = v.strip()
    raw = values.get("storeFile")
    if not raw:
        return None, "", ""
    candidate = pathlib.Path(raw)
    store = candidate if candidate.is_absolute() else ANDROID / raw
    return store, values.get("keyAlias", ""), values.get("storePassword", "")


def statement(fingerprint: str) -> list[dict]:
    return [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": PACKAGE,
                "sha256_cert_fingerprints": [fingerprint],
            },
        }
    ]


def relying_party_id() -> str:
    override = os.environ.get("PASSKEY_RP_ID")
    if override:
        return override.strip()
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8-sig").splitlines():
            if line.startswith("SUPABASE_URL="):
                return urlparse(line.split("=", 1)[1].strip()).hostname or ""
    return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rp-id", default="")
    ap.add_argument("--emit-release", action="store_true")
    args = ap.parse_args()

    print("Weekend - Digital Asset Links digest")
    print("=" * 62)

    digests: dict[str, str] = {}

    debug_ks = pathlib.Path.home() / ".android/debug.keystore"
    if debug_ks.exists():
        digests["debug"] = digest_of(debug_ks, "androiddebugkey", "android")
    else:
        digests["debug"] = MISSING
    print(f"debug   {digests['debug']}")

    store, alias, storepass = release_store()
    if store is not None and store.exists():
        digests["release"] = digest_of(store, alias, storepass)
    else:
        digests["release"] = MISSING
    print(f"release {digests['release']}")

    rp_id = args.rp_id or relying_party_id()
    print("=" * 62)
    if not rp_id:
        print("Could not determine the relying-party ID. Pass --rp-id.")
        return 1
    print(f"relying-party ID : {rp_id}")
    print(f"assetlinks URL   : https://{rp_id}/.well-known/assetlinks.json")

    if args.emit_release:
        digest = digests["release"]
        if digest == MISSING:
            print(
                "\nNo release keystore available - refusing to emit a statement "
                "with a placeholder digest."
            )
            return 1
        print(json.dumps(statement(digest), indent=2))
    else:
        if digests["debug"] != MISSING:
            print("\nDebug statement:\n" + json.dumps(statement(digests["debug"]), indent=2))
        print(
            "\nEach digest must be served in its OWN statement: a release APK "
            "signed\nby a different key will not be associated by the debug digest."
        )
        if digests["release"] == MISSING:
            print(
                "WARNING: no release keystore found. The release APK's digest "
                "is still\nunknown, so passkeys cannot work on it yet."
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
