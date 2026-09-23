# Weekend Analytics

Live dashboard: <https://zypherlabs-bit.github.io/Weekend/analytics/>

Aggregated GitHub-derived statistics for this repository — repository
visitors and Android APK downloads — rendered by `index.html` from
`data/daily.json`.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Dashboard (static, no external dependencies, no tracking scripts) |
| `data/daily.json` | Aggregated daily snapshots — the single data source |
| `../../.github/workflows/update-analytics.yml` | Daily updater (00:00 UTC / 05:30 IST) + manual dispatch |
| `../../.github/scripts/update-analytics.py` | Fetch/merge script run by the workflow |

## Data definitions

- **repository_views / repository_unique_visitors** — GitHub's repository
  traffic API (`GET /traffic/views`). GitHub exposes only a rolling
  **14-day window**; each daily run snapshots that window so history
  accumulates beyond GitHub's limit. Days outside the window are never
  overwritten. Unique counts are per-day and are *not* deduplicated across
  days ("visitor-days").
- **repository_clones / repository_unique_cloners** — GitHub's
  `GET /traffic/cloners` API. This endpoint currently returns `404` for this
  repository, so clone metrics display **N/A**.
- **apk_downloads_daily** — *snapshot-derived*: cumulative APK download
  count at today's snapshot minus the previous snapshot's cumulative count.
  The first snapshot day is `null` (no baseline yet), never an invented 0.
  This estimates downloads since the previous snapshot, not calendar-precise
  midnights.
- **apk_downloads_cumulative / total_downloads** — GitHub release asset
  `download_count` summed over all `.apk` assets, plus
  `apk.archived_downloads` (the count observed on the removed
  `Weekend-v2.2.0-supabase.apk` asset before deletion).
- **release** — latest GitHub release tag, date, APK asset, its download
  count and the published SHA-256.

No personal data is stored: no visitor names, IPs, emails, tokens or any
other identifying information — only the aggregated counters above.

## Schedule / timezone

`cron: "0 0 * * *"` is interpreted on the **UTC** clock: the snapshot runs
daily at **00:00 UTC (05:30 IST)**. `workflow_dispatch` triggers a run on
demand; GitHub's traffic data for a UTC day may lag by up to ~1–2 days, so
"today"/"yesterday" visitor rows can show `N/A` until GitHub publishes them.

## Provenance labels

- Values sourced from GitHub's API at the last snapshot are labelled
  *GitHub repository traffic* / *GitHub release assets* on the dashboard.
- Sums across multiple dates (7-day, 30-day, cumulative totals) are computed
  from **Weekend's stored snapshots** in `data/daily.json`.
- Data before `tracking_started` was backfilled once from GitHub's 14-day
  window on the tracking start date; nothing is fabricated for dates the
  system has never observed.
