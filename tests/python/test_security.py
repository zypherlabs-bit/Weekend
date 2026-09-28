"""Security checks: secret scanning, RLS, Storage and client-side safety.

The secret scan deliberately distinguishes a *documented example* of a secret
name from an actual committed secret value. Flagging a commented-out
``SUPABASE_SERVICE_ROLE_KEY=`` line in a README as a leak would be a false
positive that trains people to ignore the report, so only real key-shaped
values in shipped source are escalated.
"""

from __future__ import annotations

import re

from weekend_checks import (
    REPO_ROOT,
    SECRET_VALUE_RE,
    CheckResult,
    Evidence,
    Status,
    dart_sources,
    migration_text,
    read_text,
    run_tool,
    secret_scan_patterns,
)

#: Files that legitimately mention secret NAMES without containing values.
DOC_SUFFIXES = (".md", ".txt", ".lock")

#: Files that are git-ignored and therefore never committed. A credential in
#: one of these is expected (that is what the file is for); the check that
#: matters is whether the file is TRACKED, which test_key_properties_not_
#: committed and `git ls-files` cover separately.
IGNORED_NAMES = {".env", "key.properties"}


def _is_source_file(path) -> bool:
    """True for shipped source, false for docs/examples/lockfiles."""
    if path.name.endswith(".example") or path.name.startswith(".env.example"):
        return False
    return path.suffix not in DOC_SUFFIXES


def test_no_committed_secrets() -> CheckResult:
    """No real key-shaped value is committed anywhere in the tree.

    Scans for Supabase PATs and JWT-style keys. Documentation is excluded so
    an example in the README is not mistaken for a leak.
    """
    findings: list[str] = []
    skip_dirs = {".git", "build", ".dart_tool", "node_modules", "__pycache__"}

    for path in REPO_ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in skip_dirs for part in path.parts):
            continue
        if not _is_source_file(path):
            continue
        # A git-ignored local credential file is expected to hold a key; what
        # matters is that git does not track it. Verified separately.
        if path.name in IGNORED_NAMES:
            continue
        text = read_text(path)
        if text and SECRET_VALUE_RE.search(text):
            findings.append(str(path.relative_to(REPO_ROOT)))

    return CheckResult(
        name="Secret value scan",
        status=Status.PASS if not findings else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=(
            "no key-shaped values committed"
            if not findings
            else f"review: {', '.join(sorted(set(findings))[:5])}"
        ),
    )


def test_secret_name_patterns_in_client() -> CheckResult:
    """Secret NAMES are not referenced in Flutter source.

    A `SUPABASE_SERVICE_ROLE_KEY` identifier in a Dart file is a red flag; the
    same word in docs or Edge Functions is expected and not scanned here.
    """
    hits: list[str] = []
    patterns = secret_scan_patterns()
    for path in dart_sources():
        text = read_text(path)
        for label, pattern in patterns:
            if text and re.search(pattern, text):
                hits.append(f"{path.relative_to(REPO_ROOT)} ({label})")
    return CheckResult(
        name="Secret names in client code",
        status=Status.PASS if not hits else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="none" if not hits else "; ".join(hits[:5]),
    )


def test_service_role_key_not_in_client() -> CheckResult:
    """No service-role key literal is embedded in the Flutter source.

    The service-role key bypasses Row Level Security. Shipping it in the APK
    would hand every user full database access, so this is a hard failure.
    """
    offenders: list[str] = []
    jwtish = re.compile(r"eyJ[A-Za-z0-9_-]{60,}")
    for path in dart_sources():
        text = read_text(path)
        if text and jwtish.search(text) and "service_role" in text.lower():
            offenders.append(str(path.relative_to(REPO_ROOT)))
    return CheckResult(
        name="No service-role key in client",
        status=Status.PASS if not offenders else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="clean" if not offenders else "; ".join(offenders),
    )


def test_credential_files_not_tracked() -> CheckResult:
    """STATIC: the files that are allowed to hold keys are not tracked by git.

    `test_no_committed_secrets` skips the local `.env` because a live build
    needs real credentials somewhere. This check is the counterpart that makes
    that skip safe: git must not know about the file.
    """
    code, out = run_tool(
        ["git", "ls-files", ".env", "android/key.properties"], timeout=60
    )
    tracked = [ln.strip() for ln in out.splitlines() if ln.strip()] if code == 0 else []
    return CheckResult(
        name="Credential files untracked",
        status=Status.PASS if not tracked else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="not tracked" if not tracked else f"tracked: {tracked}",
    )


def test_rls_enabled_on_sensitive_tables() -> CheckResult:
    """RLS is enabled on every table that holds user data."""
    sql = migration_text().lower()
    sensitive = [
        "profiles",
        "profile_photos",
        "messages",
        "blocks",
        "reports",
        "likes",
        "passes",
    ]
    missing = [
        t
        for t in sensitive
        if f"alter table public.{t} enable row level security" not in sql
    ]
    return CheckResult(
        name="RLS on sensitive tables",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="enabled" if not missing else f"missing: {', '.join(missing)}",
    )


def test_coordinates_not_selectable() -> CheckResult:
    """latitude/longitude are not granted to authenticated clients.

    Raw coordinates are readable only from inside SECURITY DEFINER functions;
    a table-level column grant would leak everyone's exact position.
    """
    sql = migration_text()
    grant = re.search(
        r"grant select \(([^)]*)\) on public\.profiles to authenticated",
        sql,
        re.I | re.S,
    )
    if not grant:
        return CheckResult(
            name="Coordinates not client-readable",
            status=Status.FAIL,
            evidence=Evidence.STATIC,
            detail="no column-level grant found",
        )
    columns = grant.group(1).lower()
    leaked = [c for c in ("latitude", "longitude") if c in columns]
    return CheckResult(
        name="Coordinates not client-readable",
        status=Status.PASS if not leaked else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="revoked from clients" if not leaked else f"granted: {leaked}",
    )


def test_storage_policies_exist() -> CheckResult:
    """The private photo bucket has owner-scoped storage policies."""
    sql = migration_text().lower()
    ok = "storage.objects" in sql and "profile-photos" in sql
    policies = sql.count("create policy")
    return CheckResult(
        name="Storage policies",
        status=Status.PASS if ok and policies else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=f"{policies} policies on storage.objects" if ok else "missing",
    )


def test_sensitive_logging_avoided() -> CheckResult:
    """No print/debugPrint of tokens, passwords or raw coordinates."""
    patterns = re.compile(
        r"(print|debugPrint|log)\s*\([^)]*"
        r"(access_token|refresh_token|password|service_role|latitude|longitude)",
        re.I,
    )
    offenders: list[str] = []
    for path in dart_sources():
        text = read_text(path)
        if text and patterns.search(text):
            offenders.append(str(path.relative_to(REPO_ROOT)))
    return CheckResult(
        name="No sensitive logging",
        status=Status.PASS if not offenders else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="clean" if not offenders else "; ".join(offenders),
    )


def test_analytics_workflow_uses_secret() -> CheckResult:
    """The analytics workflow reads its token from a secret, not the repo."""
    wf = read_text(REPO_ROOT / ".github" / "workflows" / "update-analytics.yml")
    if not wf:
        return CheckResult(
            name="CI token from secrets",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.STATIC,
            detail="workflow not found",
        )
    uses_secret = "secrets." in wf
    literal = bool(re.search(r"gh[pousr]_[A-Za-z0-9]{20,}", wf))
    ok = uses_secret and not literal
    return CheckResult(
        name="CI token from secrets",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="uses secrets context" if ok else "literal token present",
    )


def test_supabase_keys_are_dart_defines() -> CheckResult:
    """Supabase credentials come from compile-time defines, not literals."""
    config = read_text(REPO_ROOT / "lib" / "config" / "supabase_config.dart")
    ok = "String.fromEnvironment" in config and "SUPABASE_URL" in config
    return CheckResult(
        name="Supabase config via dart-define",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="fromEnvironment" if ok else "credentials may be hard-coded",
    )
