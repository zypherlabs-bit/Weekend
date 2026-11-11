"""Validate the README: image paths, links, structure and asset sizes.

Run from the repository root:

    python tool/readme_capture/validate_readme.py

The link check reaches the network, so pass ``--offline`` to skip it.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
README = os.path.join(ROOT, "README.md")
MAX_IMAGE_BYTES = 1_500_000

IMAGE_RE = re.compile(r'!\[[^\]]*\]\(([^)\s]+)')
HTML_IMAGE_RE = re.compile(r'<img[^>]+src="([^"]+)"')
LINK_RE = re.compile(r'(?<!!)\[[^\]]*\]\(([^)\s]+)')
HEADING_RE = re.compile(r'^(#{1,6})\s+(.*)$', re.MULTILINE)
ANCHOR_RE = re.compile(r'\]\((#[^)]+)\)')

# Anchors other documents link into. Changing them breaks published links.
FROZEN_ANCHORS = ["#known-limitations", "#roadmap", "#qr-invitations"]

USER_AGENT = "Weekend-README-Validator/1.0"


def github_slug(heading: str) -> str:
    slug = heading.strip().lower()
    slug = re.sub(r"[^\w\s-]", "", slug, flags=re.UNICODE)
    slug = re.sub(r"\s+", "-", slug)
    return slug


def check(condition: bool, message: str, failures: list[str]) -> bool:
    if not condition:
        failures.append(message)
    return condition


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()

    with open(README, "r", encoding="utf-8") as handle:
        text = handle.read()

    failures: list[str] = []
    notes: list[str] = []

    # ---------------------------------------------------------------- images
    images = IMAGE_RE.findall(text) + HTML_IMAGE_RE.findall(text)
    check(len(images) > 0, "README contains no images", failures)
    for source in images:
        if source.startswith(("http://", "https://")):
            if not args.offline:
                request = urllib.request.Request(
                    source, method="HEAD", headers={"User-Agent": USER_AGENT}
                )
                try:
                    with urllib.request.urlopen(request, timeout=30) as response:
                        status = response.status
                except urllib.error.HTTPError as error:
                    status = error.code
                except Exception as error:  # noqa: BLE001
                    status = f"error {error}"
                check(
                    isinstance(status, int) and status < 400,
                    f"badge image failed ({status}): {source}",
                    failures,
                )
                notes.append(f"badge {source:<52} {status}")
            continue
        path = os.path.join(ROOT, source)
        if not check(os.path.isfile(path), f"missing image: {source}", failures):
            continue
        size = os.path.getsize(path)
        if not check(
            size <= MAX_IMAGE_BYTES,
            f"image over 1.5 MB: {source} ({size / 1024:.0f} KB)",
            failures,
        ):
            continue
        notes.append(f"image  {source:<40} {size / 1024:7.1f} KB")

    # ------------------------------------------------------------- headings
    headings = HEADING_RE.findall(text)
    h1 = [h for h in headings if len(h[0]) == 1]
    check(len(h1) == 1, f"expected exactly one H1, found {len(h1)}", failures)
    notes.append(f"h1    {h1[0][1] if h1 else '(none)'}")

    anchors = {github_slug(title) for _, title in headings}
    for anchor in FROZEN_ANCHORS:
        check(
            anchor.lstrip("#") in anchors,
            f"frozen anchor missing: {anchor}",
            failures,
        )

    for anchor in set(ANCHOR_RE.findall(text)):
        check(
            anchor.lstrip("#") in anchors,
            f"broken in-page anchor: {anchor}",
            failures,
        )

    # --------------------------------------------------------------- links
    external: list[str] = []
    for target in LINK_RE.findall(text):
        if target.startswith(("http://", "https://")):
            external.append(target)
        elif target.startswith("#"):
            continue
        else:
            path = os.path.join(ROOT, target.split("#")[0])
            check(os.path.exists(path), f"broken relative link: {target}", failures)

    if not args.offline:
        for url in sorted(set(external)):
            request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    status = response.status
            except urllib.error.HTTPError as error:
                status = error.code
            except Exception as error:  # noqa: BLE001
                status = f"error {error}"
            check(
                isinstance(status, int) and status < 400,
                f"external link failed ({status}): {url}",
                failures,
            )
            notes.append(f"link  {url:<40} {status}")
    else:
        notes.append(f"link  {len(set(external))} external links not checked (--offline)")

    for note in notes:
        print(note)

    if failures:
        print()
        for failure in failures:
            print(f"FAIL  {failure}")
        return 1

    print()
    print("README validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
