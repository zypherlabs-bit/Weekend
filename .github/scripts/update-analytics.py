#!/usr/bin/env python3
"""Update docs/analytics/data/daily.json from GitHub's traffic and release APIs.

Invoked daily by .github/workflows/update-analytics.yml at 00:00 UTC.

Only aggregated counters are persisted (views, unique visitors, download
counts). No visitor identities, IPs, tokens or other personal data are stored.
The GitHub token is read from the environment and never written to disk.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO = os.environ.get("GITHUB_REPOSITORY", "zypherlabs-bit/Weekend")
API = "https://api.github.com/repos/" + REPO
DATA = Path("docs/analytics/data/daily.json")
HEX = set("0123456789abcdef")

# download_count observed on Weekend-v2.2.0-supabase.apk on 2026-09-23, right
# before that asset was removed from release v2.2.0 (v2.3.0 became the active
# release). Kept so cumulative totals stay honest across asset removal.
ARCHIVED_BASELINE = 3


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _get(path_or_url: str, accept: str = "application/vnd.github+json",
         raw: bool = False):
    url = (path_or_url if path_or_url.startswith("http")
           else "https://api.github.com" + path_or_url)
    req = urllib.request.Request(url, headers={
        "Accept": accept,
        "User-Agent": "weekend-analytics-snapshot",
    })
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read()
    return body if raw else json.loads(body)


def _load() -> dict:
    if DATA.exists():
        try:
            return json.loads(DATA.read_text(encoding="utf-8"))
        except Exception as exc:  # corrupt file: rebuild from API data
            print(f"::warning::daily.json unreadable ({exc}); rebuilding")
    return {
        "schema_version": 1,
        "timezone": "UTC",
        "tracking_started": "2026-09-23",
        "generated_at": None,
        "apk": {
            "live_downloads": 0,
            "archived_downloads": ARCHIVED_BASELINE,
            "total_downloads": ARCHIVED_BASELINE,
            "asset_counts": {},
            "archived_note": (
                "Weekend-v2.2.0-supabase.apk had download_count=3 when it was "
                "removed from release v2.2.0 on 2026-09-23; the count is kept "
                "here so cumulative totals stay accurate."
            ),
        },
        "release": None,
        "days": [],
    }


def _day(data: dict, key: str) -> dict:
    for entry in data["days"]:
        if entry["date"] == key:
            return entry
    entry = {
        "date": key,
        "repository_views": None,
        "repository_unique_visitors": None,
        "repository_clones": None,
        "repository_unique_cloners": None,
        "apk_downloads_daily": None,
        "apk_downloads_cumulative": None,
    }
    data["days"].append(entry)
    return entry


def _update_traffic(data: dict) -> bool:
    """Merge GitHub's 14-day traffic window.

    Days inside the window are authoritative and overwritten; days that have
    fallen out of the window are left untouched so stored history keeps
    growing beyond GitHub's rolling limit.
    """
    ok = True
    try:
        views = _get(API + "/traffic/views")
        for item in views.get("views", []):
            entry = _day(data, item["timestamp"][:10])
            entry["repository_views"] = int(item["count"])
            entry["repository_unique_visitors"] = int(item["uniques"])
        data["traffic_window_totals"] = {
            "views": int(views.get("count", 0)),
            "unique_visitors": int(views.get("uniques", 0)),
        }
        data["traffic_fetched_at"] = _now()
    except Exception as exc:
        ok = False
        print(f"::warning::traffic/views fetch failed ({exc}); "
              "keeping stored visitor data")
    try:
        cloners = _get(API + "/traffic/cloners")
        for item in cloners.get("clones", []):
            entry = _day(data, item["timestamp"][:10])
            entry["repository_clones"] = int(item["count"])
            entry["repository_unique_cloners"] = int(item["uniques"])
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            print("::notice::traffic/cloners returned 404 (no clone data "
                  "for this repository); clone metrics stay N/A")
        else:
            print(f"::warning::traffic/cloners failed ({exc})")
    except Exception as exc:
        print(f"::warning::traffic/cloners failed ({exc})")
    return ok


def _update_releases(data: dict) -> None:
    try:
        releases = _get(API + "/releases?per_page=100")
        live = 0
        counts: dict[str, int] = {}
        for rel in releases:
            if rel.get("draft"):
                continue
            for asset in rel.get("assets", []):
                name = asset.get("name", "")
                if name.endswith(".apk"):
                    amount = int(asset.get("download_count", 0))
                    live += amount
                    counts[name] = counts.get(name, 0) + amount
        latest = _get(API + "/releases/latest")
        assets = latest.get("assets", [])
        apk = next((a for a in assets if a["name"].endswith(".apk")), None)
        sha = next((a for a in assets
                    if a["name"].endswith(".apk.sha256")), None)
        sha256 = None
        if sha:
            try:
                text = _get(
                    f"{API}/releases/assets/{sha['id']}",
                    accept="application/octet-stream", raw=True,
                ).decode("utf-8", "replace").split()
                candidate = text[0].strip().lower() if text else ""
                if len(candidate) == 64 and set(candidate) <= HEX:
                    sha256 = candidate
            except Exception as exc:
                print(f"::warning::checksum asset fetch failed ({exc})")
    except Exception as exc:
        print(f"::error::releases fetch failed ({exc})")
        sys.exit(1)

    archived = int(data.get("apk", {}).get("archived_downloads",
                                            ARCHIVED_BASELINE))
    total = live + archived
    today_key = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # Snapshot-derived daily downloads: cumulative now minus cumulative at
    # the previous snapshot. The first snapshot day stays null (no baseline).
    previous = None
    for entry in data["days"]:
        if (entry["date"] < today_key
                and entry.get("apk_downloads_cumulative") is not None):
            if previous is None or entry["date"] > previous["date"]:
                previous = entry
    today_entry = _day(data, today_key)
    if previous is None:
        today_entry["apk_downloads_daily"] = None
    else:
        delta = total - int(previous["apk_downloads_cumulative"])
        if delta < 0:
            print("::warning::cumulative APK downloads decreased; "
                  "clamping daily delta to 0")
            delta = 0
        today_entry["apk_downloads_daily"] = delta
    today_entry["apk_downloads_cumulative"] = total

    data["apk"] = {
        "live_downloads": live,
        "archived_downloads": archived,
        "total_downloads": total,
        "asset_counts": counts,
        "archived_note": data.get("apk", {}).get("archived_note", ""),
    }
    tag = latest.get("tag_name") or ""
    data["release"] = {
        "tag": tag,
        "version": tag.lstrip("v"),
        "published_at": latest.get("published_at"),
        "apk_asset": apk["name"] if apk else None,
        "apk_downloads": int(apk.get("download_count", 0)) if apk else None,
        "sha256": sha256,
    }
    print(f"release={tag or 'none'} apk_live={live} apk_total={total} "
          f"sha256={'yes' if sha256 else 'no'}")


def main() -> None:
    data = _load()
    traffic_ok = _update_traffic(data)
    _update_releases(data)
    data["days"].sort(key=lambda entry: entry["date"])
    data["generated_at"] = _now()
    DATA.parent.mkdir(parents=True, exist_ok=True)
    DATA.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"snapshot written: {DATA} days={len(data['days'])} "
          f"traffic_ok={traffic_ok} generated_at={data['generated_at']}")


if __name__ == "__main__":
    main()
