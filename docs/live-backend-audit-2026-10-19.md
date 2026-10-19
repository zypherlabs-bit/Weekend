# Live backend audit — 2026-10-19

Scope: verify the Weekend feature set against the **live** Supabase project
(`ocypgybqfushqfzisnvs`, region `ap-southeast-1`) as an authenticated user, and
apply the pending feature migrations. Everything below is reproducible with the
`tool/` scripts named in each section.

Environment note: this network firewalls the Postgres ports (`5432`/`6543`) to
both the direct host and the pooler, so `supabase db push` / `supabase migration
list` cannot reach the database. The Management API HTTPS endpoint
`POST /v1/projects/{ref}/database/query` **is** reachable, so migrations were
applied through it with `tool/apply_migration_via_api.py`, which wraps each file
and its `supabase_migrations.schema_migrations` row in a single transaction.

## 1. Migration state

Before: `001`–`028` + `030` applied (`029` deliberately held back in
`supabase/migrations-held/`).

Applied in this session, in order, each verified:

| version | name | note |
|---|---|---|
| 031 | unified_discovery_entitlements_and_modes | needed a fix, see §2 |
| 032 | like_priority_and_match_lifecycle | needed a fix, see §2 |
| 033 | support_and_message_risk | clean |
| 034 | fix_spotlight_lateral_alias | corrective, see §2 |
| 035 | search_profiles_legacy_overload_privacy_wrapper | closes finding F1, see §4 |
| 036 | harden_helper_function_grants | closes finding F2, see §4 |

After all six the live ledger reads `001`–`028` + `030`–`036`; `029` is still
absent. The authenticated probe was re-run after 036 and reports the same
**28 LIVE / 5 GUARDED / 1 DENIED / 0 ABSENT** — the grant change is not
observable to a signed-in client.

Verified with `tool/live_schema_verify.py` (diffs the live `public` schema
against a pre-migration inventory):

* tables 38 → 44: `+ user_entitlements, spotlight_windows, photo_impressions,
  support_tickets, opening_moves, discovery_surges` — RLS **enabled** on all six
* columns 295 → 352, including `likes.note`, `likes.priority_weight`,
  `matches.initiator_id`, `matches.window_opened_at`, `matches.rematch_count`,
  `matches.rematched_at`, `messages.risk_flags`, `user_settings.incognito_mode`,
  `user_settings.snooze_until`, `user_settings.travel_lat`,
  `user_settings.away_until`, `user_settings.show_online_now`
* the two overloads the migrations intentionally replace are gone:
  `get_nearby_profiles(8-arg)` and `record_like(uuid, boolean)`

## 2. Defects found and fixed

These are real bugs that would have hit any deployment with `001`–`030` already
applied — not artefacts of the tooling used here.

**(a) 031 — `search_profiles` could not be created at all.**
The migration used `create or replace` while changing the OUT row type from the
19-column 030 shape to the 22-column version. Postgres refuses that
(`42P13: cannot change return type of existing function`). Fix: an explicit
`drop function if exists public.search_profiles(<21-arg signature>)` before the
create, the same pattern 031 already used for `get_nearby_profiles` and 032 used
for `record_like`/`get_matches_for_user`.

**(b) 032 — `get_received_likes` could not be created.** Same cause: 026's
version returned 13 columns, 032 returns 15 (adds `note`, `priority_weight`).
Fix: `drop function if exists public.get_received_likes(integer, integer)`.

**(c) 031 — a latently broken spotlight join, found by the live probe, not by
compiling.** The hardened 21-arg `search_profiles` joins a lateral spotlight
subquery aliased `sw` but the lateral's select list was `select 1 as mid`, while
the outer query reads `sw.id` twice. The function compiled fine and then failed
on **every call**:

```
HTTP 400   42703: column sw.id does not exist
```

Because the app's discovery feed calls this overload, the feed was returning an
error while the advanced-search screen kept working (it uses the 13-arg
overload), which masked the defect. Shipped as migration
`034_fix_spotlight_lateral_alias.sql` (a single `create or replace`, one word
changed, OUT row type unchanged so no drop is needed).

After 034, the probe reports the hardened call healthy:
`discovery/search_profiles (21-arg, hardened) HTTP 200 rows=5`.

**(d) client — Opening Moves could never be saved (found on the device, not by
compiling).** `OpeningMoveRepository.upsertAll` upserted
`{sort_order, prompt[, photo_id]}` and never sent `user_id`. In
`public.opening_moves` (032) that column is `not null` with **no default**, and
the insert policy is `with check (user_id = auth.uid())`, so every save was
rejected:

```
HTTP 403   42501: new row violates row-level security policy for table "opening_moves"
```

The repository's `catch (_) { return false; }` turned that into a silent
failure — the editor stayed open with no visible error. Because RLS also
requires the row to be *readable* by the same owner, the empty state looked
identical before and after the attempt, which is why it read as "Save did
nothing". Fixed in `lib/repositories/engagement_repository.dart` by sending
`'user_id': me` (guarded so an unauthenticated call fails fast), matching the
owner-row pattern `PrivacyRepository.setShowOnlineNow` already used.

Evidence: `tool/opening_moves_rls_probe.py` drives the exact REST calls the
client makes, as the probe account:

```
A) shipped payload (NO user_id)  HTTP 403  42501 row-level security violation
B) fixed payload (+ user_id)     HTTP 201  [row returned]
C) read back through RLS         HTTP 200  [row returned]
D) cleanup through RLS           HTTP 204  rows left for probe: 0
DEFECT CONFIRMED + FIX PROVEN: YES
```

Then confirmed on-device against the live backend: the edited prompt saved
(green "Opening moves saved on the server."), the row was read back from
Postgres, and reopening the editor reloaded it. Two contract tests were added to
`test/database_contract_test.dart` holding the schema (`user_id` NOT NULL, no
default) and the client payload together; removing the fix makes the new test
fail.

## 3. Authenticated probe results

`tool/authenticated_probe.py` logs in the synthetic probe account and calls
every RPC the Flutter client actually calls, with the parameter names the client
sends (the list is extracted from source by `tool/extract_client_rpcs.py`, 35
distinct calls). Calls that would touch another user's data are issued with a
non-existent target id on purpose, so the only possible outcome is a guard
error.

Result: **28 LIVE, 5 GUARDED (expected guard errors), 1 DENIED (a real
permission check fired), 0 ABSENT**. No client RPC is missing from the live
project. Representative outputs:

```
likes/record_like            HTTP 400  Only verified adults can use Weekend matching.
matches/extend_match         HTTP 400  Match not found
matches/unmatch_match        HTTP 200  False
profile/set_primary_profile_photo  HTTP 403  That photo does not belong to you
privacy/set_privacy_mode     HTTP 200  {"mode": "incognito", "enabled": false}
engagement/activate_spotlight HTTP 200 {"activated": true, ...}
referral/get_referral_stats  HTTP 200  rows=1
```

Full matrix: `tool/_auth_probe_results.json`.

Entitlement path verified end-to-end: creating the probe account fired
`handle_new_user` → profile row created, and `grant_default_entitlements` →
**14 entitlements per user, all `source='system_free'`** (280 rows across the
20 existing accounts, i.e. the backfill also worked). No billing provider is
configured; entitlements are server-authoritative but uniformly free.

## 4. Findings and their resolution

Both findings were fixed and applied with the maintainer's approval; each fix has
its own migration and its own before/after evidence below.

### F1 — privacy-mode bypass via the legacy `search_profiles` overload — **privacy, high** — ✅ FIXED (migration 035)

Two overloads were live simultaneously:

| overload | called by | incognito | snooze | online-consent gating |
|---|---|---|---|---|
| 13-arg `(p_genders,…,p_page,p_page_size)` | advanced search screen — `lib/models/discovery_preferences.dart` `toRpcParams` | **no** | **no** | **no** |
| 21-arg `(p_limit,p_offset,…)` | discovery feed — `DiscoveryFilters.toRpcParams` | yes | yes | yes |

031 hardened only the 21-arg version. The 13-arg one dates from 022 and predates
023/026/028/031, and the app still calls it.

`tool/privacy_bypass_probe.py` proves it with fixtures (two synthetic accounts
at identical coordinates):

```
=== control: B discoverable, incognito OFF ===
   21-arg (discovery feed): rows=11 B_present=True
   13-arg (search screen) : rows=1  B_present=True
=== test: B is INCOGNITO ===
   21-arg (discovery feed): rows=10 B_present=False   [expected: absent]
   13-arg (search screen) : rows=1  B_present=True    [BYPASS]
VERDICT: BYPASS CONFIRMED
```

So a user who switches on incognito (or snooze, or turns online status off) is
still reachable — with `last_active_at` disclosed — through the search screen.
**Resolution — migration 035, applied.** The 13-arg overload is now a
compatibility wrapper that delegates to the hardened 21-arg function, mapping
`p_page/p_page_size → p_offset/p_limit` and projecting the old column names, so
the shipped client keeps working unchanged while inheriting the privacy
filters. No app release was needed.

It was dry-run first (`tool/dry_run_migration.py` runs the file against the live
database inside a transaction that is always rolled back, and diffs the live
function definitions before and after to prove nothing else moved), then applied
and re-probed with the same fixtures:

```
=== control: B discoverable, incognito OFF ===
   21-arg (discovery feed): rows=11 B_present=True
   13-arg (search screen) : rows=11 B_present=True
=== test: B is INCOGNITO ===
   21-arg (discovery feed): rows=10 B_present=False   [expected: absent]
   13-arg (search screen) : rows=10 B_present=False   [now also absent]
VERDICT: no bypass observed
```

Both overloads now return the same population (11 → 10 with B removed), so
incognito, snooze and online-consent are enforced no matter which screen asks.
A new static test,
`test_search_sql.py::TestSearchProfilesRpc::test_legacy_overload_delegates_to_the_hardened_one`,
fails if the wrapper ever stops delegating (verified by temporarily removing
035 and watching it fail).

### F2 — anon-executable helper functions — **defence in depth, low–medium** — ✅ FIXED (migration 036)

Several `public` functions kept PostgreSQL's default `EXECUTE TO PUBLIC`, so the
public anon key (which ships inside the APK) could call them. Most are guarded
internally (`assert_self` / `auth.uid()`); these were not:

| function | exposure |
|---|---|
| `get_user_interests(p_user_id)` | reads any user's interests (SECURITY DEFINER, no guard) |
| `approved_photo_count(p_user_id)` | counts any user's approved photos |
| `has_feature_entitlement(p_user_id, p_feature)` | probes any user's entitlements (new in 031; the client never calls it) |
| `mfa_recovery_code_hash(p_user_id, p_code)` | hashing oracle — a caller could test recovery-code guesses against **any** account without that account's session |
| `tmp_probe_dollar()` | stray test function left in the live database — debris |

**Resolution — migration 036, applied.** Anon and PUBLIC EXECUTE is revoked on
all four; `get_user_interests` keeps its `authenticated` grant because the client
calls it, the other three keep only the owner and `service_role` because they are
only ever invoked from `SECURITY DEFINER` functions (which run as the owner), and
`tmp_probe_dollar()` is dropped. Verified live with the public anon key:

```
mfa_recovery_code_hash   HTTP 401  42501 permission denied for function mfa_recovery_code_hash
approved_photo_count     HTTP 401  42501 permission denied for function approved_photo_count
has_feature_entitlement  HTTP 401  42501 permission denied for function has_feature_entitlement
get_user_interests       HTTP 401  42501 permission denied for function get_user_interests
```

and the client-facing paths were re-checked as a signed-in user:
`profile/get_user_interests`, `auth/mfa_recovery_code_count` and
`auth/consume_mfa_recovery_code` all still return `HTTP 200`. Before revoking,
the live catalogue was checked for dependents that would run as the *caller* —
no RLS policy, view, column default or check constraint references any of the
four, and every known caller (`search_profiles`, `activate_spotlight`,
`set_privacy_mode`, `set_travel_location`, `record_like`,
`consume_mfa_recovery_code`) is `SECURITY DEFINER`.

**Still open (deliberately out of scope).** 57 project functions still carry
`EXECUTE TO PUBLIC` — the remainder are trigger functions (not reachable over
PostgREST) and guarded RPCs whose callers are checked by `assert_self`. A
blanket "no anon EXECUTE" policy would be a larger ACL change than this finding
justifies and is left as a follow-up.

## 5. Release artefact finding

The published `Weekend-v2.8.0-release.apk` was built **without**
`--dart-define=SUPABASE_URL/SUPABASE_ANON_KEY`. Verified by scanning every entry
of the APK: the control string `not connected to a backend` is present in
`libapp.so`, but neither the project URL nor the anon-key prefix appears
anywhere. An installed build therefore runs in the backend-less mode the app
detects and **cannot sign in**.

Rebuilt for this session's screenshot run through the repository's own
`tool/build_release.py` (which reads the credentials from the git-ignored `.env`
and never writes them to a tracked file):

* `build/app/outputs/flutter-apk/app-release.apk` — 122.9 MB, `versionCode 13`,
  `versionName 2.8.0`, `SUPABASE_URL` **and** the anon key present in every
  `libapp.so`
* signed with the release keystore, signer SHA-256
  `15b2f91aebc85bb26b647e94f9b3223689410b8ecf29dde798f9c5b0cc8c2594` — this
  matches the fingerprint documented in the README, so the rebuild uses the same
  release identity as the published asset
* `Weekend-v2.8.0-release.apk.sha256` regenerated alongside it

**Resolved by publishing `v2.8.1`.** The defective asset was **not** replaced in
place — the maintainer chose a new tag, so `v2.8.0` stays as published with its
warning intact and `v2.8.1` (`versionCode 14`) becomes the current release. It is
built the same way, with the same release keystore (signer SHA-256
`15b2f91aebc85bb26b647e94f9b3223689410b8ecf29dde798f9c5b0cc8c2594`), so it
installs as an upgrade over the release-signed `v2.8.0`. The `Release` workflow
already refuses to build when the `SUPABASE_URL` / `SUPABASE_ANON_KEY` secrets
are missing or are placeholders, which is the check that would have caught this.

## 6. On-device run against the live backend

A release APK built as above was installed on an Android 17 emulator
(`emulator-5554`, 1080×2400) and driven with `adb`. The app signed in with the
synthetic probe account (`weekend.probe.agent@example.com`) against the live
project. Every screen below reflects server state; none of it was mocked.

| what was done | result |
|---|---|
| sign in with email + password | succeeded; session restored across an app restart |
| location permission + `adb emu geo fix` | discovery feed loaded live cards |
| Profile tab | rendered the signed-in account's true state |
| Settings → Privacy & Availability | Incognito toggled on/off; the description changed from the **server** response |
| Profile → Spotlight & Photo Insights | rendered the server's real spotlight window (`ends_at`) |
| Profile → Photo Verification | reported the true state: "Your profile is not verified yet." |
| Profile → Opening Moves | saved a prompt (after the §2(d) fix) → row in Postgres → reloaded on reopen |

Screenshot-handling rules applied: the discovery feed renders **real people's
profiles**, so no feed capture is published; every published capture is of the
synthetic probe account's own surfaces. A verification badge initially shown on
that account came from a test fixture (`is_photo_verified = true` set over SQL,
not a real review); the fixture was reset before the screenshots were taken, so
the published captures show an unverified account and match the audit trail.

The account is a **synthetic probe account**, and the published screenshots say
so. They are not captures of a real user's data and must not be presented as
such.

## 7. Static-test suite: the pre-existing baseline, and what this work changed

`python -m pytest tests/python` reports **15 failures on a clean `HEAD`
checkout**, before any change in this session. Confirmed by running the same
files in a `git worktree` at the baseline commit and diffing the failure sets,
so the regression question is answered with a control and not an assumption.

They are **stale text assertions, not behavioural regressions**: each greps the
concatenated migration SQL for the exact wording of a pre-031 definition of
`search_profiles`. 031 replaced both overloads, so the literal strings moved
even though the invariants they protect still hold. The three most
security-relevant ones were re-checked **against the live database** rather than
assumed:

| failing test | live check | result |
|---|---|---|
| `test_floor_is_unconditional[search_profiles]` | `pg_get_functiondef` of the 13-arg overload | `p.date_of_birth is not null and date_part('years', age(p.date_of_birth))::int >= 18` **is present**; the 21-arg overload clamps `p_age_min` to ≥18 and filters `between coalesce(p_age_min,18) and …` |
| `test_user_scoped_rpcs_assert_self` | same | `assert_self` **is present** in both overloads |
| `test_discovery_never_returns_coordinates` | `pg_get_function_result` of both overloads | both return `distance_km`; **neither** returns `latitude`/`longitude`/raw `lat`/`lon` |

The other thirteen failures are the same class of stale wording, split between
`test_search_sql.py` (filter / pagination / interests / photo-minimum phrasings
and `TestMigration027SchemaIntegrity::test_no_travel_mode_column`) and
`test_adult_only_enforcement.py` (the same invariants asserted against the old
body). The fourteenth is the scanner false positive described next.

**What this work changed.** `tests/python/conftest.py` gained
`function_definitions()` / `_body_at()` so a test can inspect the whole
*definition chain* for a function name instead of one concatenated blob, and
`function_body` was refactored to share them. On top of that:

* applying 035 broke four assertions that matched the 13-arg overload by its old
  body — those were rewritten to assert the invariant across the chain (the
  caller-ownership guard, the unconditional 18+ floor, no raw coordinates)
  rather than deleted;
* `test_discovery_never_returns_coordinates` is the one **baseline** failure this
  work resolved;
* one test was **added**,
  `test_legacy_overload_delegates_to_the_hardened_one`, which fails if the
  035 wrapper ever stops delegating to the hardened function. Verified
  non-vacuous: it fails when 035 is hidden from the migration set and passes
  when it is restored.

So the suite now reports **14 failures against the 15-failure baseline: zero
new, one resolved** (`14 failed, 330 passed, 1 skipped`), and every remaining
failure is still the stale-wording class described above.

One failure is a **scanner false positive**: `test_no_jwt_in_shipped_code` flags
`tool/_inject_migrations.sh:19` and `:25`. That file (tracked since `8d80803`)
holds base64 blobs of the migration SQL, and two blobs decode to SQL comments
containing JSON examples — `{"Sunday": false} is NOT contained in
{"Sunday": true}` and `{"prompt": str, "answer": str}`. The `eyJ…` prefix the
scanner matches is the base64 of `{"`. **No credential is present**; the
scanner cannot distinguish base64-of-JSON from base64-of-JWT.

`tool/seo_audit.py`'s `download.version_match` failure — `docs/installation.md`
pointed at `Weekend-v2.6.0-release.apk` while `pubspec.yaml` was on `2.8.0` — is
also fixed: `installation.md` now points at the current `v2.8.1` asset, so the
check passes.
