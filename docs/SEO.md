# SEO — Weekend Repository & README

Audience: maintainers who edit the [README](../README.md) or repository
metadata and want the project to rank for the searches it actually serves.

This page documents the keyword strategy, the required README structure, the
image rules, and the automated audit that enforces all of it
(`tool/seo_audit.py`). Nothing here describes planned work — every rule below
is currently enforced or currently true.

---

## 1. Target keywords

| Tier | Query intent | Keywords |
|------|--------------|----------|
| Primary | Find the app | **free dating app**, **free dating app for Android**, **Weekend dating app** |
| Secondary | Category match | open source dating app, location-based dating app, nearby dating app, dating app with real-time chat |
| Long tail | Specific features | dating app with weekend plans, privacy-first dating app, dating app without paywall, Flutter Supabase dating app, dating app open source MIT |
| Developer | Contributor intent | open source dating app Flutter, Supabase PostGIS dating app, Flutter location-based app example |

**Placement rules (enforced by `tool/seo_audit.py`):**

- H1 contains `Free Dating App` and `Open Source`.
- The first paragraph under the H1 restates the primary keyword naturally
  within the first ~500 characters (this is what search engines snippet).
- `free dating app` appears naturally in the Why Weekend, Free dating and FAQ
  sections — but not stuffed: the audit warns above a repeat threshold.
- Secondary keywords appear at least once each: `location-based`, `open source`,
  `real-time`, `paywall`, `privacy`, `Android`.

## 2. README structure (user-first, in this order)

1. **Hero** — logo, single H1, tagline, badges, primary CTA links.
2. **Screenshots** — visual proof; images must be honest (see §3).
3. **Why Weekend?** — benefit table (scannable).
4. **How it works** — numbered onboarding steps.
5. **Features** — one `###` per feature, stable anchors.
6. **Free dating on Weekend** — the no-paywall value proposition.
7. **Download Weekend** — CTA to the current release (version-matched).
8. **FAQ** — ≥ 10 question-form `###` headings (`What/Is/Does/How/Where`).
9. **Open source**, **Known limitations**, **Roadmap** — trust signals.
10. **Developer documentation last** — stack, architecture, setup, testing.

Rules:

- Exactly **one H1**. Every other heading is `##` or `###`.
- The table of contents must link to real anchors (the audit resolves every
  `#anchor` against the actual headings).
- Anchors that other documents link to are **frozen**:
  `#known-limitations`, `#roadmap`, `#qr-invitations` (referenced from
  `SECURITY.md`, `docs/location-discovery.md`, `docs/qr-invitations.md`).
  Renaming those headings breaks external deep links — don't.

## 3. Image rules (screenshots and artwork)

- Every `<img>` needs meaningful **alt text** containing the keyword context
  (for example: *"Weekend artwork — friends meeting, free dating app for Android"*).
- Images must be **honest**: artwork is labelled artwork; only captures of the
  running app may be called screenshots. The README's Screenshots section mixes
  real captures (onboarding, sign-up) with clearly labelled brand artwork and
  carries an explicit honesty note explaining which is which; captures of the
  signed-in experience remain a roadmap item.
- **No duplicate files.** The audit hashes every image in `docs/screenshots/`
  and `docs/assets/` and fails on identical bytes stored twice. One image = one
  file; reference it, don't copy it.
- Keep images ≤ 1.5 MB (the audit warns above that).

## 4. Download links and version drift

- The README names the current APK exactly as published:
  `Weekend-v<version>-release.apk` with `<version>` equal to the
  `version:` field in `pubspec.yaml`.
- Always link `releases/latest` for the "always current" path **and** a direct
  versioned asset for the "download now" path.
- Never write `releases/latest/download/Weekend-vX.Y.Z-…` — `latest` resolves
  dynamically while the filename is static, so it 404s on the next release.
  (`tests/python/test_release.py` enforces this too.)
- When you bump `pubspec.yaml` and tag a release, update README and
  `docs/installation.md` in the same PR — the audit fails otherwise.

## 5. Repository metadata (GitHub settings, outside the README)

Recommended repo description:

> Weekend — free, open-source dating app for Android. Location-based discovery,
> real-time chat, weekend plans. Flutter + Supabase (MIT).

Suggested topics: `dating-app`, `flutter`, `supabase`, `android`,
`open-source`, `location-based`, `postgis`, `realtime`, `dart`, `social-app`.
(Competitor names as topics are rejected by
`tests/python/test_release.py::test_github_topics_legitimate`.)

Social preview image: `docs/assets/weekend-logo.jpg`.

## 6. The audit

```bash
python tool/seo_audit.py            # static checks only (default)
python tool/seo_audit.py --online   # + verify the GitHub latest release matches pubspec
```

Output is one line per check with a `PASS`, `FAIL` or `WARNING` verdict, then a
summary. Exit code is `1` if any check FAILs, `0` otherwise. The tool is
**read-only**: it never modifies the repository.

| Group | What it checks |
|-------|----------------|
| Structure | single H1, required sections in required order, TOC anchors resolve |
| Keywords | primary/secondary keyword presence, stuffing threshold |
| FAQ | ≥ 10 question-form headings |
| Download | versioned APK matches pubspec, no `latest/download` pins, CTA present |
| Links | every relative README link resolves to a file or an anchor |
| Images | exist, have alt text, ≤ 1.5 MB, no duplicate bytes |
| SEO docs | `docs/SEO.md` exists and documents the primary keyword |

Run it before every release PR; keep it green.

## 7. What this page does not claim

- No ranking guarantees, no search-console data — none exists for this
  repository yet.
- JSON-LD/FAQ schema markup is not applicable to a GitHub README; if the project
  ships a website later, reuse the README FAQ content as `FAQPage` schema
  there.
