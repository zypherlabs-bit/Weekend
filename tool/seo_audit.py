#!/usr/bin/env python3
"""SEO & README integrity audit for the Weekend repository.

READ-ONLY: this tool never modifies the repository. It prints one line per
check with a PASS / FAIL / WARNING verdict and exits non-zero if any check
FAILs.

Usage:
    python tool/seo_audit.py            # static checks (default)
    python tool/seo_audit.py --online   # + verify GitHub latest release tag
                                         #   matches pubspec.yaml
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
README = REPO_ROOT / "README.md"
SEO_DOC = REPO_ROOT / "docs" / "SEO.md"
PUBSPEC = REPO_ROOT / "pubspec.yaml"
SCREENSHOT_DIRS = (REPO_ROOT / "docs" / "screenshots", REPO_ROOT / "docs" / "assets")

#: Docs that advertise the download to end users (mirrors tests/python/test_release.py).
MARKETING_DOCS = ("README.md", "docs/installation.md", "docs/getting-started.md")

APK_NAME_RE = re.compile(r"Weekend-v(\d+\.\d+\.\d+)-release\.apk")
HEADING_RE = re.compile(r"^(?:>\s*)*(#{1,6})\s+(.*?)\s*$")
MD_LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)\s]+)\)")
IMG_TAG_RE = re.compile(r"<img\s+([^>]*)>")
SRC_RE = re.compile(r'src="([^"]+)"')
ALT_RE = re.compile(r'alt="([^"]*)"')

#: Sections that must exist, in this relative order (user-first landing page).
REQUIRED_ORDER = (
    "screenshots",
    "why-weekend",
    "how-it-works",
    "features",
    "free-dating-on-weekend",
    "download-weekend",
    "faq",
    "open-source",
    "known-limitations",
    "roadmap",
    "developer-documentation",
    "license",
)

#: Keywords that must appear somewhere in the README (case-insensitive).
REQUIRED_PHRASES = (
    "free dating app",
    "location-based",
    "open source",
    "android",
    "real-time",
    "paywall",
    "privacy",
    "flutter",
    "supabase",
    "passkey",
)

PRIMARY_KEYWORD = "free dating app"
STUFFING_THRESHOLD = 15  # occurrences of the primary keyword before WARNING
FAQ_MIN_QUESTIONS = 10
IMAGE_MAX_BYTES = 1_500_000
QUESTION_STARTERS = ("what", "is", "does", "how", "where", "who", "why", "can", "are")

results: list[tuple[str, str, str]] = []


def record(status: str, name: str, detail: str) -> None:
    results.append((status, name, detail))


def slugify(text: str) -> str:
    """Approximate GitHub's heading anchor algorithm.

    Lowercase, strip markdown emphasis and non [alphanumeric space hyphen]
    characters, then turn each space into a hyphen. Multiple hyphens are kept —
    GitHub does not collapse them.
    """
    text = re.sub(r"[`*_~]", "", text.strip().lower())
    text = "".join(ch for ch in text if ch.isalnum() or ch in " -")
    return text.replace(" ", "-")


def extract_headings(markdown: str) -> list[tuple[int, str, str]]:
    headings: list[tuple[int, str, str]] = []
    in_fence = False
    for line in markdown.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = HEADING_RE.match(line)
        if m:
            level = len(m.group(1))
            title = m.group(2)
            headings.append((level, title, slugify(title)))
    return headings


def pubspec_version() -> str | None:
    if not PUBSPEC.exists():
        return None
    m = re.search(
        r"^version:\s*(\d+\.\d+\.\d+)", PUBSPEC.read_text(encoding="utf-8"), re.M
    )
    return m.group(1) if m else None


def check_structure(readme: str, headings: list[tuple[int, str, str]]) -> None:
    h1s = [t for lvl, t, _ in headings if lvl == 1]
    if len(h1s) == 1:
        record("PASS", "structure.h1", f"exactly one H1: {h1s[0][:60]}")
    else:
        record("FAIL", "structure.h1", f"expected 1 H1, found {len(h1s)}")

    if h1s:
        low = h1s[0].lower()
        missing = [k for k in ("weekend", "dating app", "open source") if k not in low]
        if missing:
            record("FAIL", "structure.h1_keywords", f"H1 missing: {missing}")
        else:
            record("PASS", "structure.h1_keywords", "H1 carries product + keyword")

    slugs = [s for _, _, s in headings]
    positions: list[int] = []
    missing_sections: list[str] = []
    for slug in REQUIRED_ORDER:
        if slug in slugs:
            positions.append(slugs.index(slug))
        else:
            missing_sections.append(slug)
    if missing_sections:
        record("FAIL", "structure.sections", f"missing sections: {missing_sections}")
    elif positions != sorted(positions):
        record("FAIL", "structure.sections", "required sections out of order")
    else:
        record("PASS", "structure.sections", f"{len(REQUIRED_ORDER)} sections, ordered")

    # Every internal #anchor link must resolve to a real heading.
    anchors = {s for _, _, s in headings}
    used = {m.group(2) for m in MD_LINK_RE.finditer(readme) if m.group(2).startswith("#")}
    broken = sorted(a for a in used if a.lstrip("#") not in anchors)
    if broken:
        record("FAIL", "structure.anchors", f"unresolved anchors: {broken}")
    else:
        record("PASS", "structure.anchors", f"{len(used)} internal anchors resolve")


def check_keywords(readme: str) -> None:
    low = readme.lower()
    missing = [p for p in REQUIRED_PHRASES if p not in low]
    if missing:
        record("FAIL", "keywords.present", f"missing phrases: {missing}")
    else:
        record(
            "PASS", "keywords.present", f"{len(REQUIRED_PHRASES)} required phrases present"
        )

    count = low.count(PRIMARY_KEYWORD)
    if count > STUFFING_THRESHOLD:
        record(
            "WARNING",
            "keywords.stuffing",
            f'"{PRIMARY_KEYWORD}" appears {count}x (>{STUFFING_THRESHOLD})',
        )
    elif count == 0:
        record("FAIL", "keywords.primary", f'primary keyword "{PRIMARY_KEYWORD}" absent')
    else:
        record("PASS", "keywords.primary", f'"{PRIMARY_KEYWORD}" appears {count}x (natural)')


def check_faq(readme: str) -> None:
    lines = readme.splitlines()
    start = end = None
    for i, line in enumerate(lines):
        if line.startswith("## FAQ"):
            start = i
        elif start is not None and line.startswith("## ") and i > start:
            end = i
            break
    if start is None:
        record("FAIL", "faq.section", "no '## FAQ' section")
        return
    body = lines[start : end if end is not None else len(lines)]
    questions = [
        h
        for _, h, _ in extract_headings("\n".join(body))
        if h.lower().startswith(QUESTION_STARTERS)
    ]
    if len(questions) >= FAQ_MIN_QUESTIONS:
        record("PASS", "faq.questions", f"{len(questions)} question headings")
    else:
        record("FAIL", "faq.questions", f"{len(questions)} < {FAQ_MIN_QUESTIONS} required")


def check_download(readme: str) -> None:
    version = pubspec_version()
    if not version:
        record("FAIL", "download.pubspec", "could not read version from pubspec.yaml")
        return
    record("PASS", "download.pubspec", f"pubspec version {version}")

    stale: list[str] = []
    for rel in MARKETING_DOCS:
        path = REPO_ROOT / rel
        if not path.exists():
            stale.append(f"{rel} MISSING")
            continue
        for named in APK_NAME_RE.findall(path.read_text(encoding="utf-8")):
            if named != version:
                stale.append(f"{rel} -> v{named}")
    if stale:
        record("FAIL", "download.version_match", f"expected v{version}; stale: {stale}")
    else:
        record("PASS", "download.version_match", f"all marketing docs name v{version}")

    m = re.search(r"Current version:\s*(\d+\.\d+\.\d+)", readme)
    if m and m.group(1) == version:
        record("PASS", "download.headline_version", f"headline states {version}")
    elif m:
        record("FAIL", "download.headline_version", f"headline {m.group(1)} != {version}")
    else:
        record("WARNING", "download.headline_version", "no 'Current version: X.Y.Z' found")

    if "releases/latest" in readme:
        record("PASS", "download.latest_link", "links releases/latest")
    else:
        record("FAIL", "download.latest_link", "no releases/latest link")

    if f"/releases/download/v{version}/Weekend-v{version}-release.apk" in readme:
        record("PASS", "download.direct_link", f"direct v{version} APK link present")
    else:
        record("FAIL", "download.direct_link", "no direct versioned APK link")

    pinned = re.findall(r"releases/latest/download/\S*", readme)
    bad = [p for p in pinned if APK_NAME_RE.search(p)]
    if bad:
        record("FAIL", "download.no_latest_pins", f"versioned latest/download pins: {bad}")
    else:
        record("PASS", "download.no_latest_pins", "no latest/download version pins")


def check_links(readme: str) -> None:
    broken: list[str] = []
    checked = 0
    for m in MD_LINK_RE.finditer(readme):
        target = m.group(2)
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        path_part = target.split("#", 1)[0]
        if not path_part:
            continue
        checked += 1
        if not (REPO_ROOT / path_part).exists():
            broken.append(target)
    if broken:
        record("FAIL", "links.relative", f"broken relative links: {broken}")
    else:
        record("PASS", "links.relative", f"{checked} relative links resolve")


def check_images(readme: str) -> None:
    missing: list[str] = []
    no_alt: list[str] = []
    oversized: list[str] = []
    seen_src: list[str] = []

    for m in IMG_TAG_RE.finditer(readme):
        attrs = m.group(1)
        src_m, alt_m = SRC_RE.search(attrs), ALT_RE.search(attrs)
        if not src_m:
            continue
        src = src_m.group(1)
        if src.startswith(("http://", "https://")):
            continue
        seen_src.append(src)
        path = REPO_ROOT / src
        if not path.exists():
            missing.append(src)
            continue
        if not alt_m or not alt_m.group(1).strip():
            no_alt.append(src)
        elif "weekend" not in alt_m.group(1).lower():
            no_alt.append(f"{src} (alt lacks 'Weekend')")
        if path.stat().st_size > IMAGE_MAX_BYTES:
            oversized.append(f"{src} ({path.stat().st_size // 1024} KB)")

    if missing:
        record("FAIL", "images.exist", f"missing: {missing}")
    else:
        record("PASS", "images.exist", f"{len(seen_src)} README images exist")
    if no_alt:
        record("FAIL", "images.alt", f"missing/weak alt text: {no_alt}")
    else:
        record("PASS", "images.alt", "all images have descriptive alt text")
    if oversized:
        record("WARNING", "images.size", f"over 1.5 MB: {oversized}")

    # Duplicate bytes anywhere in the image folders = one image stored twice.
    by_hash: dict[str, list[str]] = {}
    for folder in SCREENSHOT_DIRS:
        if not folder.is_dir():
            continue
        for path in sorted(folder.iterdir()):
            if not path.is_file() or path.suffix.lower() not in {
                ".jpg",
                ".jpeg",
                ".png",
                ".webp",
            }:
                continue
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            by_hash.setdefault(digest, []).append(str(path.relative_to(REPO_ROOT)))
    dupes = {h: files for h, files in by_hash.items() if len(files) > 1}
    if dupes:
        detail = "; ".join(" = ".join(v) for v in dupes.values())
        record("FAIL", "images.no_duplicates", f"duplicate image bytes: {detail}")
    else:
        record("PASS", "images.no_duplicates", "no duplicate image files")


def check_seo_doc() -> None:
    if not SEO_DOC.exists():
        record("FAIL", "seo.doc", "docs/SEO.md missing")
        return
    text = SEO_DOC.read_text(encoding="utf-8").lower()
    if PRIMARY_KEYWORD in text:
        record("PASS", "seo.doc", "docs/SEO.md documents the primary keyword")
    else:
        record("FAIL", "seo.doc", f'docs/SEO.md does not mention "{PRIMARY_KEYWORD}"')


def check_online(version: str | None) -> None:
    url = "https://api.github.com/repos/zypherlabs-bit/Weekend/releases/latest"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=20) as resp:
            tag = json.loads(resp.read().decode("utf-8", "replace")).get("tag_name", "")
    except Exception as exc:  # noqa: BLE001
        record("WARNING", "release.latest", f"unreachable: {type(exc).__name__}")
        return
    latest = tag.lstrip("v")
    if version and latest == version:
        record("PASS", "release.latest", f"GitHub latest {tag} matches pubspec")
    else:
        record("FAIL", "release.latest", f"GitHub latest {tag} != pubspec {version}")


def main() -> int:
    parser = argparse.ArgumentParser(description="SEO & README audit (read-only)")
    parser.add_argument(
        "--online", action="store_true", help="also verify the GitHub release tag"
    )
    args = parser.parse_args()

    if not README.exists():
        record("FAIL", "readme.exists", "README.md missing")
    else:
        readme = README.read_text(encoding="utf-8")
        headings = extract_headings(readme)
        check_structure(readme, headings)
        check_keywords(readme)
        check_faq(readme)
        check_download(readme)
        check_links(readme)
        check_images(readme)
    check_seo_doc()

    version = pubspec_version()
    if args.online:
        check_online(version)
    else:
        record("WARNING", "release.latest", "skipped (run with --online to verify)")

    width = max(len(name) for _, name, _ in results)
    for status, name, detail in results:
        print(f"{status:<7} {name:<{width}}  {detail}")

    fails = sum(1 for s, _, _ in results if s == "FAIL")
    warns = sum(1 for s, _, _ in results if s == "WARNING")
    passes = sum(1 for s, _, _ in results if s == "PASS")
    print("-" * 72)
    print(f"PASS: {passes}   FAIL: {fails}   WARNING: {warns}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())


